//
//  CommunityGuardianService.swift
//  Guardian
//
//  Orchestrates Community Guardian: an opt-in, additional layer of nearby
//  verified community members who can be paged during an SOS to assist —
//  never to confront — while professional emergency services (112/contacts)
//  remain the primary, untouched response path.
//
//  Real path: candidates discovered over MeshService (MultipeerConnectivity)
//  broadcast their availability; requests/responses travel the same way.
//  Simulated fallback: seeded demo CommunityGuardian rows (DemoController)
//  used when no real peer is eligible, so a presentation always has a path to
//  demonstrate. Both paths are ranked by the same GuardianMatchingEngine and
//  produce identical CommunityGuardianRequest rows — the UI only distinguishes
//  them via `provenance` labeling, never separate logic.
//
//  Privacy: a CommunityGuardianRequest never carries a coordinate, only an
//  approximate distance. The Guardian side only resolves the requester's real
//  location after the request is accepted, and that access ends the moment
//  the search is cancelled/ended (see endSearch/cancelSearch).
//

import Foundation
import SwiftData
import CoreLocation
import Observation

@Observable
final class CommunityGuardianService {

    // MARK: Local opt-in profile (this device, if the user became a Guardian)

    private(set) var localGuardianID: UUID?
    private(set) var localAvailability: GuardianAvailability = .offline

    // MARK: Requester-side state (this device is having an emergency)

    private(set) var flowState: CommunityGuardianFlowState = .idle
    private(set) var activeRequests: [CommunityGuardianRequest] = []
    private(set) var currentEmergencyID: UUID?
    private(set) var currentSearchRadius: Double = 0

    // MARK: Guardian-side state (this device is acting as a Guardian)

    private(set) var incomingRequest: CommunityGuardianRequest?
    /// Only populated after `incomingRequest` is accepted — see privacy note above.
    private(set) var incomingEmergencyCoordinate: CLLocationCoordinate2D?

    private let engine = GuardianMatchingEngine()
    private var modelContext: ModelContext?
    private weak var mesh: MeshService?
    private var searchTask: Task<Void, Never>?

    // Escalating radius, notify at most 3 per step. These numbers reflect
    // the ACTUAL range of the underlying transport — MultipeerConnectivity
    // (Bluetooth/WiFi Direct mesh), not a real GPS-radius search. There is no
    // backend/push infrastructure in this app, so a Guardian can only ever be
    // reached if their phone is within real physical mesh range with the app
    // open and broadcasting — realistically the same room/building, not a
    // neighborhood. Using 500m/1km/2km here would be dishonest: it would
    // imply a search radius the transport can never actually achieve.
    private let radiusSteps: [Double] = [30, 60, 100]
    private let perStepTimeout: TimeInterval = 20
    private let requestExpiry: TimeInterval = 45
    private let notifyLimit = 3

    func configure(modelContext: ModelContext, mesh: MeshService) {
        self.modelContext = modelContext
        self.mesh = mesh
        self.localGuardianID = localGuardianRow()?.guardianID
    }

    // MARK: - Opt-in (Guardian side)

    func becomeGuardian(displayName: String,
                        level: GuardianVerificationLevel,
                        capabilities: [GuardianCapability]) {
        guard let ctx = modelContext else { return }
        if let existing = localGuardianRow() {
            existing.displayName = displayName
            existing.verificationLevel = level
            existing.capabilities = capabilities
            existing.updatedAt = .now
        } else {
            let guardian = CommunityGuardian(displayName: displayName,
                                             verificationLevel: level,
                                             availability: .offline,
                                             capabilities: capabilities,
                                             isLocalUser: true,
                                             provenance: .real)
            ctx.insert(guardian)
            localGuardianID = guardian.guardianID
        }
        try? ctx.save()
    }

    var localGuardianProfile: CommunityGuardian? { localGuardianRow() }

    func setAvailability(_ availability: GuardianAvailability, location: CLLocationCoordinate2D?) {
        guard let guardian = localGuardianRow() else { return }
        guardian.availability = availability
        guardian.updatedAt = .now
        if availability == .available, let location {
            guardian.latitude = location.latitude
            guardian.longitude = location.longitude
            guardian.lastLocationUpdate = .now
        }
        try? modelContext?.save()
        localAvailability = availability

        if availability == .available, let mesh, let coordinate = guardian.coordinate {
            broadcastAvailability(guardian, coordinate: coordinate, mesh: mesh)
        }
    }

    private func localGuardianRow() -> CommunityGuardian? {
        guard let ctx = modelContext else { return nil }
        let descriptor = FetchDescriptor<CommunityGuardian>(
            predicate: #Predicate { $0.isLocalUser == true })
        return try? ctx.fetch(descriptor).first
    }

    // MARK: - Requester side — entry point from AppModel.activateSOS

    /// Starts a Guardian search for `emergencyID`. No-ops if a search is
    /// already active for the same emergency (duplicate-emergency guard).
    /// Fire-and-forget from the caller's perspective — progress is observed
    /// via `flowState`/`activeRequests`.
    func startSearch(emergencyID: UUID, category: EmergencySource, coordinate: CLLocationCoordinate2D) {
        guard currentEmergencyID != emergencyID else { return }
        currentEmergencyID = emergencyID
        activeRequests = []
        flowState = .searching
        currentSearchRadius = radiusSteps.first ?? 500
        logExternalEvent(emergencyID: emergencyID, label: "Community Guardian search started")

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.runSearchLoop(emergencyID: emergencyID, category: category, coordinate: coordinate)
        }
    }

    /// The user cancelled — stop searching and release any granted access.
    func cancelSearch(emergencyID: UUID) {
        guard currentEmergencyID == emergencyID else { return }
        searchTask?.cancel()
        searchTask = nil
        for request in activeRequests where request.status == .pending {
            request.status = .cancelled
        }
        try? modelContext?.save()
        resetRequesterState()
    }

    /// The emergency resolved — access to it must end (privacy requirement).
    func endSearch(emergencyID: UUID) {
        cancelSearch(emergencyID: emergencyID)
        if incomingRequest?.emergencyID == emergencyID {
            incomingRequest = nil
            incomingEmergencyCoordinate = nil
        }
    }

    private func resetRequesterState() {
        currentEmergencyID = nil
        currentSearchRadius = 0
    }

    private func runSearchLoop(emergencyID: UUID, category: EmergencySource,
                               coordinate: CLLocationCoordinate2D) async {
        for radius in radiusSteps {
            guard !Task.isCancelled else { return }
            currentSearchRadius = radius

            let candidates = eligibleCandidatePool()
            let excluded = Set(activeRequests.map(\.guardianID))
            let ranked = engine.rank(
                candidates: candidates,
                for: GuardianMatchRequest(emergencyCoordinate: coordinate, emergencyCategory: category,
                                          radiusMeters: radius, excludedGuardianIDs: excluded),
                limit: notifyLimit)

            if !ranked.isEmpty {
                for candidate in ranked {
                    send(requestTo: candidate, emergencyID: emergencyID, category: category)
                }
                flowState = .found
                logExternalEvent(emergencyID: emergencyID,
                                 label: "\(ranked.count) eligible guardian(s) notified within \(Int(radius))m")

                if await waitForAcceptance(timeout: perStepTimeout) {
                    return
                }
            }
        }

        guard !Task.isCancelled else { return }
        flowState = .failed
        logExternalEvent(emergencyID: emergencyID,
                         label: "No Community Guardian was available — other emergency alerts remain active")
    }

    private func waitForAcceptance(timeout: TimeInterval) async -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if Task.isCancelled { return true }
            if activeRequests.contains(where: { $0.status == .accepted }) {
                flowState = .responding
                return true
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    /// Guardians known on this device: real mesh-discovered rows plus any
    /// seeded demo rows — both are plain `CommunityGuardian` rows, ranked
    /// identically. `isLocalUser` rows never match their own emergency.
    private func eligibleCandidatePool() -> [CommunityGuardian] {
        guard let ctx = modelContext else { return [] }
        let all = (try? ctx.fetch(FetchDescriptor<CommunityGuardian>())) ?? []
        return all.filter { !$0.isLocalUser }
    }

    /// Sends over mesh for a real peer; for a demo seed there is no real
    /// device to message, so the request simply waits to be auto-accepted by
    /// DemoController (see CommunityGuardianService.autoAcceptTopDemoCandidate).
    private func send(requestTo candidate: GuardianMatchCandidate, emergencyID: UUID, category: EmergencySource) {
        guard let ctx = modelContext else { return }
        let provenance: DataProvenance = candidate.guardian.isDemoSeed ? .simulated : .real
        let request = CommunityGuardianRequest(
            emergencyID: emergencyID,
            guardianID: candidate.guardian.guardianID,
            approximateDistanceMeters: candidate.distanceMeters,
            emergencyCategory: category,
            provenance: provenance,
            expiresAt: .now.addingTimeInterval(requestExpiry))
        ctx.insert(request)
        try? ctx.save()
        activeRequests.append(request)

        guard provenance == .real, let mesh else { return }
        struct GuardianRequestPayload: Encodable {
            let requestID: String, emergencyID: String
            let approximateDistanceMeters: Double, categoryRaw: String
        }
        if let payload = try? JSONEncoder().encode(GuardianRequestPayload(
            requestID: request.requestID.uuidString, emergencyID: emergencyID.uuidString,
            approximateDistanceMeters: candidate.distanceMeters, categoryRaw: category.rawValue)) {
            mesh.originate(RelayPacket(type: .guardianRequest, payload: payload))
        }
    }

    private func broadcastAvailability(_ guardian: CommunityGuardian, coordinate: CLLocationCoordinate2D, mesh: MeshService) {
        struct AvailabilityPayload: Encodable {
            let guardianID: String, displayName: String
            let verificationLevelRaw: String, capabilitiesRaw: [String]
            let lat: Double, lon: Double
        }
        if let payload = try? JSONEncoder().encode(AvailabilityPayload(
            guardianID: guardian.guardianID.uuidString, displayName: guardian.displayName,
            verificationLevelRaw: guardian.verificationLevelRaw, capabilitiesRaw: guardian.capabilitiesRaw,
            lat: coordinate.latitude, lon: coordinate.longitude)) {
            mesh.originate(RelayPacket(type: .guardianAvailability, payload: payload))
        }
    }

    // MARK: - Mesh packet ingestion — wired from AppModel's mesh.onPacketReceived

    func handle(_ packet: RelayPacket) {
        switch packet.messageType {
        case .guardianAvailability: handleAvailability(packet)
        case .guardianRequest:      handleIncomingRequest(packet)
        case .guardianResponse:     handleResponse(packet)
        case .emergency, .locationUpdate, .text, .ack: break
        }
    }

    private struct AvailabilityPayloadDecoded: Decodable {
        let guardianID: String, displayName: String
        let verificationLevelRaw: String, capabilitiesRaw: [String]
        let lat: Double, lon: Double
    }

    private func handleAvailability(_ packet: RelayPacket) {
        guard let ctx = modelContext,
              let payload = try? JSONDecoder().decode(AvailabilityPayloadDecoded.self, from: packet.payload),
              let guardianID = UUID(uuidString: payload.guardianID) else { return }

        let descriptor = FetchDescriptor<CommunityGuardian>(
            predicate: #Predicate { $0.guardianID == guardianID })
        if let existing = try? ctx.fetch(descriptor).first {
            existing.availability = .available
            existing.latitude = payload.lat
            existing.longitude = payload.lon
            existing.lastLocationUpdate = .now
            existing.updatedAt = .now
        } else {
            let guardian = CommunityGuardian(
                guardianID: guardianID, displayName: payload.displayName,
                verificationLevel: GuardianVerificationLevel(rawValue: payload.verificationLevelRaw) ?? .community,
                availability: .available,
                capabilities: payload.capabilitiesRaw.compactMap(GuardianCapability.init),
                latitude: payload.lat, longitude: payload.lon, lastLocationUpdate: .now,
                provenance: .real)
            ctx.insert(guardian)
        }
        try? ctx.save()
    }

    private struct GuardianRequestPayloadDecoded: Decodable {
        let requestID: String, emergencyID: String
        let approximateDistanceMeters: Double, categoryRaw: String
    }

    private func handleIncomingRequest(_ packet: RelayPacket) {
        guard localAvailability == .available,
              let payload = try? JSONDecoder().decode(GuardianRequestPayloadDecoded.self, from: packet.payload),
              let requestID = UUID(uuidString: payload.requestID),
              let emergencyID = UUID(uuidString: payload.emergencyID),
              let ctx = modelContext,
              let localID = localGuardianID else { return }

        let request = CommunityGuardianRequest(
            requestID: requestID, emergencyID: emergencyID, guardianID: localID,
            approximateDistanceMeters: payload.approximateDistanceMeters,
            emergencyCategory: EmergencySource(rawValue: payload.categoryRaw) ?? .other,
            provenance: .real, expiresAt: .now.addingTimeInterval(requestExpiry))
        ctx.insert(request)
        try? ctx.save()
        incomingRequest = request
    }

    private struct ResponsePayloadDecoded: Decodable {
        let requestID: String, accepted: Bool
    }

    private func handleResponse(_ packet: RelayPacket) {
        guard let payload = try? JSONDecoder().decode(ResponsePayloadDecoded.self, from: packet.payload),
              let requestID = UUID(uuidString: payload.requestID),
              let index = activeRequests.firstIndex(where: { $0.requestID == requestID }) else { return }

        activeRequests[index].status = payload.accepted ? .accepted : .declined
        if payload.accepted {
            activeRequests[index].acceptedAt = .now
            flowState = .responding
            if let emergencyID = currentEmergencyID {
                logExternalEvent(emergencyID: emergencyID, label: "Community Guardian accepted")
            }
        }
        try? modelContext?.save()
    }

    // MARK: - Guardian-side actions

    func acceptIncomingRequest() {
        guard let request = incomingRequest, let ctx = modelContext else { return }
        request.status = .accepted
        request.acceptedAt = .now
        try? ctx.save()

        if let guardian = localGuardianRow() {
            guardian.availability = .responding
            guardian.activeEmergencyID = request.emergencyID
            try? ctx.save()
        }
        incomingEmergencyCoordinate = emergencyCoordinate(for: request.emergencyID)
        respond(to: request, accepted: true)
    }

    func declineIncomingRequest() {
        guard let request = incomingRequest, let ctx = modelContext else { return }
        request.status = .declined
        try? ctx.save()
        respond(to: request, accepted: false)
        incomingRequest = nil
        incomingEmergencyCoordinate = nil
    }

    /// Guardian can no longer continue — treated like a decline for this
    /// prototype. TODO: re-enter the requester's search loop from the
    /// current radius so another candidate is notified; the existing SOS/
    /// call/contacts flow is unaffected either way since it never depends on
    /// Guardian outcome.
    func cannotContinue() {
        completeGuardianSide(status: .cancelled)
    }

    func completeAssistance() {
        completeGuardianSide(status: .completed)
        if let request = incomingRequest, let emergencyID = currentEmergencyID, request.emergencyID == emergencyID {
            flowState = .completed
        }
    }

    private func completeGuardianSide(status: CommunityGuardianRequestStatus) {
        guard let request = incomingRequest, let ctx = modelContext else { return }
        request.status = status
        request.completedAt = .now
        try? ctx.save()
        if let guardian = localGuardianRow() {
            guardian.availability = .available
            guardian.activeEmergencyID = nil
            try? ctx.save()
        }
        incomingRequest = nil
        incomingEmergencyCoordinate = nil
    }

    private func respond(to request: CommunityGuardianRequest, accepted: Bool) {
        guard let mesh, request.provenance == .real else { return }
        struct ResponsePayload: Encodable { let requestID: String; let accepted: Bool }
        if let payload = try? JSONEncoder().encode(ResponsePayload(requestID: request.requestID.uuidString, accepted: accepted)) {
            mesh.originate(RelayPacket(type: .guardianResponse, payload: payload))
        }
    }

    private func emergencyCoordinate(for emergencyID: UUID) -> CLLocationCoordinate2D? {
        guard let ctx = modelContext else { return nil }
        let descriptor = FetchDescriptor<EmergencyPacket>(
            predicate: #Predicate { $0.packetID == emergencyID })
        return try? ctx.fetch(descriptor).first?.coordinate
    }

    // MARK: - Demo support

    /// Drives the first `.simulated` active request through the exact same
    /// accept path a real Guardian would use, so the demo exercises real
    /// service code rather than a shadow implementation.
    func autoAcceptTopDemoCandidate() {
        guard let index = activeRequests.firstIndex(where: { $0.provenance == .simulated && $0.status == .pending }) else { return }
        activeRequests[index].status = .accepted
        activeRequests[index].acceptedAt = .now
        try? modelContext?.save()
        flowState = .responding
        if let emergencyID = currentEmergencyID {
            logExternalEvent(emergencyID: emergencyID, label: "Community Guardian accepted (demo)", provenance: .simulated)
        }
    }

    // MARK: - Timeline

    /// Single write path for EmergencyTimelineEvent — called from here and
    /// from AppModel, so timeline logging never has two divergent code paths.
    func logExternalEvent(emergencyID: UUID, label: String, provenance: DataProvenance = .real) {
        guard let ctx = modelContext else { return }
        ctx.insert(EmergencyTimelineEvent(emergencyID: emergencyID, label: label, provenance: provenance))
        try? ctx.save()
    }
}
