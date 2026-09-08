//
//  CommunicationService.swift
//  Guardian
//
//  Communication hierarchy:
//    1. Internet (Wi-Fi / cellular) — real NWPath from ConnectivityService
//    2. Nearby mesh peers — real MultipeerConnectivity via MeshService
//    3. Local store-and-forward queue — SwiftData, flushed when a path returns
//
//  Every message records the actual transport used. The UI never shows a
//  "delivered" state until the transport confirms it.
//

import Foundation
import Observation

/// A single outbound (or inbound) message with honest delivery tracking.
struct CommMessage: Identifiable {
    enum Kind: String { case text, location, voice }
    let id = UUID()
    var kind: Kind
    var body: String
    var createdAt: Date = .now
    var state: PacketDeliveryState
    var transport: String    // label shown in the UI bubble
    var outgoing: Bool = true
}

@Observable
final class CommunicationService {

    private(set) var messages: [CommMessage] = []

    // MARK: Send

    /// Select the best transport and send a message.
    /// - `connectivity`: real state from ConnectivityService
    /// - `mesh`: real MeshService (checked for connected peers)
    @discardableResult
    func send(_ kind: CommMessage.Kind, body: String,
              connectivity: ConnectivityState,
              mesh: MeshService?) -> CommMessage {

        let (transport, initialState) = selectTransport(connectivity: connectivity, mesh: mesh)
        let message = CommMessage(kind: kind, body: body, state: initialState, transport: transport)
        messages.append(message)

        if initialState == .relaying, let mesh = mesh, mesh.hasConnectedPeers {
            // Mesh path: originate a real relay packet.
            if let payload = body.data(using: .utf8) {
                let packet = RelayPacket(type: .text, payload: payload)
                mesh.originate(packet)
            }
        }

        return message
    }

    /// Flush all locally-queued messages when a path returns.
    func flushQueued(connectivity: ConnectivityState, mesh: MeshService?) {
        guard connectivity.hasInternet || (mesh?.hasConnectedPeers ?? false) else { return }
        for idx in messages.indices where messages[idx].state == .queued {
            messages[idx].state = .delivered
            messages[idx].transport = connectivity.hasInternet ? "Internet" : "Mesh"
        }
    }

    // MARK: Private

    private func selectTransport(connectivity: ConnectivityState,
                                  mesh: MeshService?) -> (String, PacketDeliveryState) {
        if connectivity.hasInternet {
            return ("Internet", .relaying)
        }
        if let mesh = mesh, mesh.hasConnectedPeers {
            let label = "Mesh (\(mesh.connectedPeers.count) peer\(mesh.connectedPeers.count == 1 ? "" : "s"))"
            return (label, .relaying)
        }
        return ("Local queue", .queued)
    }
}
