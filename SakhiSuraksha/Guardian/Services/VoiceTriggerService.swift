//
//  VoiceTriggerService.swift
//  Guardian
//
//  Real, on-device phrase detection for Discreet SOS — but foreground-only.
//  iOS does not allow unrestricted background microphone / continuous voice
//  recognition, so this only listens while the app is open and the user has
//  explicitly started a listening session (RootView stops it when the app
//  leaves the foreground). The phrase match is exact (case-insensitive
//  substring), not a "dangerous tone" detector — Guardian never claims to
//  infer emotional state from voice. Confidence is a fixed nominal value,
//  documented as supplementary and non-authoritative, since SFSpeechRecognizer
//  does not provide a phrase-level confidence score.
//
//  Designed so a production wake-word engine can later conform to the same
//  VoiceTriggerService protocol without touching call sites.
//

import Foundation
import Observation

#if os(iOS)
import Speech
import AVFoundation
#endif

protocol VoiceTriggerService: AnyObject {
    var isListening: Bool { get }
    var isAuthorized: Bool { get }
    func requestAuthorization() async -> Bool
    /// Starts listening for `phrase` (case-insensitive substring match).
    /// `onMatch` is called with a nominal, non-authoritative confidence value.
    func startListening(phrase: String, onMatch: @escaping (Double) -> Void)
    func stopListening()
}

#if os(iOS)

@Observable
final class RealVoiceTriggerService: VoiceTriggerService {
    private(set) var isListening = false
    private(set) var isAuthorized = false

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var targetPhrase: String = ""
    @ObservationIgnored private var onMatch: ((Double) -> Void)?
    /// True only while the caller wants us actively listening — distinguishes an
    /// internal restart (utterance finished, keep going) from an explicit stop.
    @ObservationIgnored private var wantsListening = false

    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        isAuthorized = (speechStatus == .authorized) && micGranted
        return isAuthorized
    }

    func startListening(phrase: String, onMatch: @escaping (Double) -> Void) {
        guard isAuthorized, !phrase.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        stopListening()

        wantsListening = true
        targetPhrase = phrase.lowercased()
        self.onMatch = onMatch
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        request = req

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            request = nil
            return
        }

        isListening = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString.lowercased()
                if text.contains(self.targetPhrase) {
                    self.onMatch?(1.0) // nominal, non-authoritative confidence
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                let shouldRestart = self.wantsListening
                self.stopListening()
                // Relisten so a single utterance isn't a one-shot window, but only
                // if the caller hasn't explicitly stopped us in the meantime.
                if shouldRestart, self.isAuthorized, let onMatch = self.onMatch {
                    self.startListening(phrase: phrase, onMatch: onMatch)
                }
            }
        }
    }

    func stopListening() {
        wantsListening = false
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

#endif

@Observable
final class MockVoiceTriggerService: VoiceTriggerService {
    private(set) var isListening = false
    var isAuthorized = false

    func requestAuthorization() async -> Bool {
        isAuthorized = true
        return true
    }

    func startListening(phrase: String, onMatch: @escaping (Double) -> Void) {
        isListening = true
    }

    func stopListening() {
        isListening = false
    }
}
