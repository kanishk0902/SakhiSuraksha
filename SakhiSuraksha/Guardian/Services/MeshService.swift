//
//  MeshService.swift
//  Guardian
//
//  Real peer-to-peer mesh using MultipeerConnectivity. Each Guardian device
//  advertises and browses for other Guardian devices. Packets are forwarded
//  hop-by-hop with TTL decrements and duplicate detection. Undeliverable
//  packets are stored locally (SwiftData) and flushed when peers appear.
//
//  Wire packet: RelayPacket (Codable JSON over MCSession reliable channel)
//  Transport security: MCSession with .required encryption (TLS equivalent)
//

import Foundation
import MultipeerConnectivity
import SwiftData
import Observation

// MARK: - Wire-format packet

/// The on-the-wire relay envelope. Relay devices forward this intact,
/// only modifying `senderDisplayName`, `ttl`, and `hopCount`.
struct RelayPacket: Codable, Identifiable {
    var id: UUID { packetID }
    let packetID: UUID
    let originDeviceID: String       // Guardian device UUID (persists across restarts)
    var senderDisplayName: String    // immediate MCPeerID sender; mutated each hop
    let messageType: MeshMessageType
    let payload: Data                // opaque to relay nodes; future: end-to-end encrypted
    var ttl: Int                     // decremented each hop; packet dropped when 0
    var hopCount: Int                // incremented each hop
    let createdAt: Date

    init(type: MeshMessageType, payload: Data, ttl: Int = 7) {
        self.packetID = UUID()
        self.originDeviceID = MeshService.deviceID
        self.senderDisplayName = ""
        self.messageType = type
        self.payload = payload
        self.ttl = ttl
        self.hopCount = 0
        self.createdAt = .now
    }
}

enum MeshMessageType: String, Codable {
    case emergency      = "emergency"
    case locationUpdate = "location"
    case text           = "text"
    case ack            = "ack"
    // Community Guardian — payloads defined in CommunityGuardianService, kept
    // out of MeshService itself so relay/routing logic stays payload-agnostic.
    case guardianAvailability = "guardianAvailability"
    case guardianRequest      = "guardianRequest"
    case guardianResponse     = "guardianResponse"
}

// MARK: - Live peer model

struct MeshPeer: Identifiable {
    var id: String { peerID.displayName }
    let peerID: MCPeerID
    var state: MCSessionState
    let discoveredAt: Date
    var lastSeen: Date
}

extension MCSessionState {
    var guardianLabel: String {
        switch self {
        case .notConnected: return "Not Connected"
        case .connecting:   return "Connecting…"
        case .connected:    return "Connected"
        @unknown default:   return "Unknown"
        }
    }
    var guardianSymbol: String {
        switch self {
        case .notConnected: return "xmark.circle"
        case .connecting:   return "arrow.2.circlepath"
        case .connected:    return "checkmark.circle.fill"
        @unknown default:   return "questionmark.circle"
        }
    }
}

// MARK: - MeshService

@Observable
final class MeshService: NSObject {

    // MARK: Persistent device identity

    /// A stable UUID that identifies this Guardian installation.
    static let deviceID: String = {
        let key = "guardian.mesh.deviceID"
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let v = UUID().uuidString
        UserDefaults.standard.set(v, forKey: key)
        return v
    }()

    // MARK: Observable state (@MainActor via project setting)

    private(set) var peers: [String: MeshPeer] = [:]
    private(set) var pendingPackets: [RelayPacket] = []
    private(set) var isAdvertising = false
    private(set) var isBrowsing = false
    private(set) var lastError: String?

    var connectedPeers: [MeshPeer] {
        peers.values.filter { $0.state == .connected }
            .sorted { $0.discoveredAt < $1.discoveredAt }
    }

    var allPeers: [MeshPeer] {
        peers.values.sorted { $0.discoveredAt < $1.discoveredAt }
    }

    var hasConnectedPeers: Bool { !connectedPeers.isEmpty }

    /// Called on the main actor when this device is the intended recipient.
    var onPacketReceived: ((RelayPacket) -> Void)?

    // MARK: MPC objects
    // nonisolated(unsafe): MPC objects are thread-safe by design; accessed
    // from both MainActor and MPC callback threads.

    @ObservationIgnored nonisolated(unsafe) private var _session: MCSession!
    @ObservationIgnored nonisolated(unsafe) private var _advertiser: MCNearbyServiceAdvertiser!
    @ObservationIgnored nonisolated(unsafe) private var _browser: MCNearbyServiceBrowser!

    private var seenIDs: Set<UUID> = []   // MainActor; mutated only in Task { @MainActor }
    private var modelContext: ModelContext?

    // Guardian mesh service type — must be ≤15 chars, lowercase alphanumeric + hyphens
    private let serviceType = "guardian-mesh"

    override init() {
#if canImport(UIKit)
        let deviceBaseName = UIDevice.current.name
#else
        let deviceBaseName = Host.current().localizedName ?? "Mac"
#endif
        // Keep display name within MCPeerID's 63-char limit
        let displayName = String(deviceBaseName.prefix(55)) + "-" + Self.deviceID.prefix(6)
        let peerID = MCPeerID(displayName: displayName)
        super.init()

        _session = MCSession(peer: peerID, securityIdentity: nil,
                             encryptionPreference: .required)
        _session.delegate = self

        _advertiser = MCNearbyServiceAdvertiser(peer: peerID,
                                                discoveryInfo: ["app": "guardian", "ver": "1"],
                                                serviceType: serviceType)
        _advertiser.delegate = self

        _browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        _browser.delegate = self
    }

    // MARK: Lifecycle

    func configure(modelContext ctx: ModelContext) {
        modelContext = ctx
        loadPersistedQueue()
    }

    func start() {
        guard !isAdvertising, !isBrowsing else { return }
        _advertiser.startAdvertisingPeer()
        _browser.startBrowsingForPeers()
        isAdvertising = true
        isBrowsing = true
    }

    func stop() {
        _advertiser.stopAdvertisingPeer()
        _browser.stopBrowsingForPeers()
        _session.disconnect()
        isAdvertising = false
        isBrowsing = false
    }

    // MARK: Sending

    /// Originate a new packet from this device.
    func originate(_ packet: RelayPacket) {
        var p = packet
        p.senderDisplayName = _session.myPeerID.displayName
        seenIDs.insert(p.packetID)
        transmit(p)
    }

    /// Flush stored queue to all currently connected peers.
    func flushQueue() {
        let targets = _session.connectedPeers
        guard !targets.isEmpty else { return }
        let snapshot = pendingPackets
        pendingPackets.removeAll()
        clearPersistedQueue()
        for p in snapshot { rawSend(p, to: targets) }
    }

    // MARK: Internals

    private func transmit(_ packet: RelayPacket) {
        let targets = _session.connectedPeers
        if targets.isEmpty {
            enqueue(packet)
        } else {
            rawSend(packet, to: targets)
        }
    }

    private func rawSend(_ packet: RelayPacket, to peers: [MCPeerID]) {
        guard !peers.isEmpty, let data = encode(packet) else { return }
        do {
            try _session.send(data, toPeers: peers, with: .reliable)
        } catch {
            enqueue(packet)
        }
    }

    private func handleReceived(data: Data, from sender: MCPeerID) {
        guard var packet = try? JSONDecoder().decode(RelayPacket.self, from: data) else { return }
        guard !seenIDs.contains(packet.packetID) else { return } // duplicate
        seenIDs.insert(packet.packetID)

        // Deliver to this device's app layer
        onPacketReceived?(packet)

        // Forward to other peers if TTL allows (never echo back to sender)
        guard packet.ttl > 0 else { return }
        packet.ttl -= 1
        packet.hopCount += 1
        packet.senderDisplayName = _session.myPeerID.displayName

        let forward = _session.connectedPeers.filter { $0 != sender }
        if forward.isEmpty {
            enqueue(packet)
        } else {
            rawSend(packet, to: forward)
        }
    }

    // MARK: Store-and-forward persistence

    private func enqueue(_ packet: RelayPacket) {
        pendingPackets.append(packet)
        persistPacket(packet)
    }

    private func encode(_ packet: RelayPacket) -> Data? { try? JSONEncoder().encode(packet) }

    private func persistPacket(_ packet: RelayPacket) {
        guard let ctx = modelContext, let data = encode(packet) else { return }
        ctx.insert(PersistedRelayPacket(packetID: packet.packetID.uuidString,
                                        data: data, createdAt: packet.createdAt))
        try? ctx.save()
    }

    private func loadPersistedQueue() {
        guard let ctx = modelContext else { return }
        let records = (try? ctx.fetch(FetchDescriptor<PersistedRelayPacket>())) ?? []
        pendingPackets = records.compactMap { r in
            guard let p = try? JSONDecoder().decode(RelayPacket.self, from: r.data) else { return nil }
            seenIDs.insert(p.packetID)
            return p
        }
    }

    private func clearPersistedQueue() {
        guard let ctx = modelContext else { return }
        let records = (try? ctx.fetch(FetchDescriptor<PersistedRelayPacket>())) ?? []
        records.forEach { ctx.delete($0) }
        try? ctx.save()
    }
}

// MARK: - MCSessionDelegate

extension MeshService: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID,
                             didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .connected:
                if peers[peerID.displayName] != nil {
                    peers[peerID.displayName]?.state = .connected
                    peers[peerID.displayName]?.lastSeen = .now
                } else {
                    peers[peerID.displayName] = MeshPeer(peerID: peerID, state: .connected,
                                                          discoveredAt: .now, lastSeen: .now)
                }
                flushQueue() // try to deliver queued packets immediately
            case .connecting:
                peers[peerID.displayName]?.state = .connecting
                peers[peerID.displayName]?.lastSeen = .now
            case .notConnected:
                peers[peerID.displayName]?.state = .notConnected
                peers[peerID.displayName]?.lastSeen = .now
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data,
                             fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in self?.handleReceived(data: data, from: peerID) }
    }

    // Unused stream/resource callbacks — required by protocol
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream,
                             withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession,
                             didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession,
                             didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?,
                             withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MeshService: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, _session) // auto-accept all Guardian invitations
        Task { @MainActor [weak self] in
            guard let self, peers[peerID.displayName] == nil else { return }
            peers[peerID.displayName] = MeshPeer(peerID: peerID, state: .connecting,
                                                  discoveredAt: .now, lastSeen: .now)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor [weak self] in
            self?.isAdvertising = false
            self?.lastError = "Advertising failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MeshService: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        // Only invite devices that explicitly identify as Guardian
        guard info?["app"] == "guardian" else { return }
        browser.invitePeer(peerID, to: _session, withContext: nil, timeout: 10)
        Task { @MainActor [weak self] in
            guard let self, peers[peerID.displayName] == nil else { return }
            peers[peerID.displayName] = MeshPeer(peerID: peerID, state: .connecting,
                                                  discoveredAt: .now, lastSeen: .now)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.peers[peerID.displayName]?.state = .notConnected
            self?.peers[peerID.displayName]?.lastSeen = .now
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak self] in
            self?.isBrowsing = false
            self?.lastError = "Discovery failed: \(error.localizedDescription)"
        }
    }
}
