//
//  EmergencyService.swift
//  Guardian
//
//  Orchestrates the SOS lifecycle: builds a persisted EmergencyPacket, starts
//  relaying it over the mesh, and manages explicitly user-initiated evidence
//  capture. High-impact actions (calling emergency services) are never automatic.
//
//  Evidence capture uses AVFoundation for real audio recording.
//  Guardian never records silently — a capture always starts with explicit user
//  action and a clearly visible indicator.
//

import Foundation
import SwiftData
import CoreLocation
import Observation

#if os(iOS)
import AVFoundation
#endif

@Observable
final class EmergencyService {

    // MARK: SOS state

    private(set) var isSOSActive = false
    private(set) var activatedAt: Date?
    private(set) var currentPacket: EmergencyPacket?

    // MARK: Evidence capture state

    private(set) var isRecording = false
    private(set) var recordingKind: EvidenceKind?
    private(set) var recordingStartedAt: Date?
    private(set) var currentEvidence: EmergencyEvidence?
    private(set) var microphonePermission: PermissionState = .unknown

    #if os(iOS)
    @ObservationIgnored private var audioRecorder: AVAudioRecorder?
    @ObservationIgnored private var recordingURL: URL?
    #endif

    enum PermissionState { case unknown, granted, denied }

    init() { refreshMicrophonePermission() }

    private func refreshMicrophonePermission() {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted:      microphonePermission = .granted
        case .denied:       microphonePermission = .denied
        case .undetermined: microphonePermission = .unknown
        @unknown default:   microphonePermission = .unknown
        }
        #endif
    }

    func requestMicrophonePermission() async {
        #if os(iOS)
        let granted = await AVAudioApplication.requestRecordPermission()
        microphonePermission = granted ? .granted : .denied
        #endif
    }

    // MARK: SOS

    @discardableResult
    func activateSOS(location: CLLocationCoordinate2D,
                     safetyState: SafetyState,
                     riskScore: Int,
                     message: String,
                     senderID: String,
                     mesh: MeshService,
                     context: ModelContext,
                     source: EmergencySource = .manual) -> EmergencyPacket {
        isSOSActive = true
        activatedAt = .now

        let packet = EmergencyPacket(
            latitude: location.latitude,
            longitude: location.longitude,
            safetyState: .emergency,
            riskScore: riskScore,
            message: message,
            senderID: senderID,
            source: source)
        context.insert(packet)
        try? context.save()
        currentPacket = packet

        // Build and send the wire-format relay packet
        struct SOSPayload: Encodable {
            let packetID: String; let message: String
            let lat: Double; let lon: Double; let senderID: String
        }
        if let payload = try? JSONEncoder().encode(SOSPayload(
            packetID: packet.packetID.uuidString, message: message,
            lat: location.latitude, lon: location.longitude, senderID: senderID)) {
            let relay = RelayPacket(type: .emergency, payload: payload)
            mesh.originate(relay)
        }

        return packet
    }

    /// Adopts a packet that was already created and persisted elsewhere —
    /// used to finish a Guardian Action Button trigger, which writes its own
    /// EmergencyPacket directly to SwiftData from a background App Intent
    /// process (no AppModel/EmergencyService instance available there) and
    /// marks it .queued. On next app launch, AppModel finds that packet and
    /// calls this instead of activateSOS, so it's completed once rather than
    /// duplicated into a second packet.
    func adopt(queuedPacket packet: EmergencyPacket, mesh: MeshService) {
        isSOSActive = true
        activatedAt = packet.timestamp
        currentPacket = packet
        packet.deliveryState = .created

        struct SOSPayload: Encodable {
            let packetID: String; let message: String
            let lat: Double; let lon: Double; let senderID: String
        }
        if let payload = try? JSONEncoder().encode(SOSPayload(
            packetID: packet.packetID.uuidString, message: packet.message,
            lat: packet.latitude, lon: packet.longitude, senderID: packet.senderID)) {
            let relay = RelayPacket(type: .emergency, payload: payload)
            mesh.originate(relay)
        }
    }

    func resolveSOS() {
        isSOSActive = false
        activatedAt = nil
        currentPacket = nil
        stopEvidence(context: nil)
    }

    // MARK: Evidence (always user-initiated, never silent)

    func startEvidence(kind: EvidenceKind,
                       location: CLLocationCoordinate2D,
                       safetyState: SafetyState,
                       journeyID: UUID?,
                       context: ModelContext) {
        guard !isRecording else { return }

        var fileName: String? = nil

        #if os(iOS)
        if kind == .audio {
            fileName = beginAudioRecording()
        }
        // Video/photo: file is handled by the UI layer (CameraView / PHPicker).
        // The evidence record stores metadata; the actual media is managed separately.
        #endif

        let evidence = EmergencyEvidence(
            kind: kind,
            latitude: location.latitude,
            longitude: location.longitude,
            safetyState: safetyState,
            journeyID: journeyID,
            localFileName: fileName)
        context.insert(evidence)
        try? context.save()

        isRecording = true
        recordingKind = kind
        recordingStartedAt = .now
        currentEvidence = evidence
    }

    func stopEvidence(context: ModelContext?) {
        guard isRecording, let started = recordingStartedAt else {
            isRecording = false; recordingKind = nil; currentEvidence = nil
            return
        }
        let duration = Date.now.timeIntervalSince(started)

        #if os(iOS)
        audioRecorder?.stop()
        audioRecorder = nil
        if let url = recordingURL {
            currentEvidence?.localFileName = url.lastPathComponent
            recordingURL = nil
        }
        #endif

        currentEvidence?.durationSeconds = duration
        if let ctx = context { try? ctx.save() }

        isRecording = false
        recordingKind = nil
        recordingStartedAt = nil
        currentEvidence = nil
    }

    // MARK: AVAudioRecorder

    #if os(iOS)
    /// Configure AVAudioSession and start an AVAudioRecorder. Returns the
    /// file's name (last path component) on success, nil on failure.
    @discardableResult
    private func beginAudioRecording() -> String? {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch { return nil }

        guard session.recordPermission == .granted else { return nil }

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("guardian-evidence-\(UUID().uuidString).m4a")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            return url.lastPathComponent
        } catch {
            recordingURL = nil
            return nil
        }
    }
    #endif
}
