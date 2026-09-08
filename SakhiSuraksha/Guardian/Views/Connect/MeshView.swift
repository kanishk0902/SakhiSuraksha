//
//  MeshView.swift
//  Guardian
//
//  Displays REAL MultipeerConnectivity peer states and the persisted relay
//  packet queue. No simulated nodes — what you see is what is actually
//  happening on the device via Bluetooth/Wi-Fi peer-to-peer.
//

import SwiftUI
import SwiftData
import MultipeerConnectivity

struct MeshView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \EmergencyPacket.timestamp, order: .reverse) private var packets: [EmergencyPacket]

    var body: some View {
        ScrollView {
            VStack(spacing: GuardianTheme.cardSpacing) {
                statusCard
                peersCard
                queueCard
                infoCard
            }
            .padding()
        }
        .navigationTitle("Mesh Network")
        .inlineNavigationTitle()
    }

    // MARK: Discovery status

    private var statusCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    GuardianSectionHeader(title: "Guardian Mesh",
                                          systemImage: "point.3.connected.trianglepath.dotted")
                    Spacer()
                    ProvenanceBadge(provenance: .real)
                }
                HStack(spacing: 16) {
                    statusPill("Advertising",
                               active: app.mesh.isAdvertising,
                               symbol: "antenna.radiowaves.left.and.right")
                    statusPill("Searching",
                               active: app.mesh.isBrowsing,
                               symbol: "magnifyingglass")
                }
                if let err = app.mesh.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(GuardianTheme.alert)
                }
            }
        }
    }

    private func statusPill(_ label: String, active: Bool, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption)
            Text(label).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(active ? GuardianTheme.safe.opacity(0.18) : Color.secondary.opacity(0.12))
        .foregroundStyle(active ? GuardianTheme.safe : .secondary)
        .clipShape(Capsule())
    }

    // MARK: Live peers

    private var peersCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Nearby Guardian Devices",
                                      systemImage: "iphone.radiowaves.left.and.right")
                if app.mesh.allPeers.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title2).foregroundStyle(.secondary)
                        Text("No peers found")
                            .font(.subheadline.weight(.semibold))
                        Text("Guardian is searching for other Guardian devices nearby over Bluetooth and Wi-Fi Direct. Both devices must have Guardian installed and open.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    ForEach(app.mesh.allPeers) { peer in
                        peerRow(peer)
                        if peer.id != app.mesh.allPeers.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func peerRow(_ peer: MeshPeer) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(stateColor(peer.state).opacity(0.18))
                Image(systemName: peer.state.guardianSymbol)
                    .foregroundStyle(stateColor(peer.state))
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.peerID.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("Last seen \(peer.lastSeen.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(peer.state.guardianLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(stateColor(peer.state))
        }
    }

    private func stateColor(_ state: MCSessionState) -> Color {
        switch state {
        case .connected:    return GuardianTheme.safe
        case .connecting:   return GuardianTheme.caution
        case .notConnected: return .secondary
        @unknown default:   return .secondary
        }
    }

    // MARK: Relay queue

    private var queueCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    GuardianSectionHeader(title: "Emergency Packets",
                                          systemImage: "shippingbox.fill")
                    Spacer()
                    if !packets.isEmpty {
                        Button("Flush Queue") {
                            app.mesh.flushQueue()
                        }
                        .font(.caption)
                    }
                }
                if packets.isEmpty {
                    Text("No packets yet. Packets appear here when an SOS is activated.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(packets) { packet in
                    HStack(spacing: 12) {
                        Image(systemName: packet.deliveryState.symbol)
                            .foregroundStyle(packet.deliveryState.color)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(packet.message).font(.subheadline).lineLimit(1)
                            Text("\(packet.timestamp.formatted(date: .omitted, time: .standard)) · TTL \(packet.ttl) · \(packet.hopCount) hops")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(packet.deliveryState.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(packet.deliveryState.color)
                    }
                    if packet.packetID != packets.last?.packetID { Divider() }
                }
                // Pending relay packets (in-memory queue)
                if !app.mesh.pendingPackets.isEmpty {
                    Divider()
                    Label("\(app.mesh.pendingPackets.count) relay packet(s) queued for next available peer",
                          systemImage: "tray.and.arrow.down.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Info

    private var infoCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("How Guardian mesh works", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                Text("Guardian uses MultipeerConnectivity (Bluetooth + Wi-Fi Direct) to discover and connect with other Guardian devices. Emergency packets are forwarded hop-by-hop toward any device that has an internet connection. Only devices with Guardian installed participate.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Packets are encrypted end-to-end by the MCSession TLS channel and survive temporary disconnections via local persistence.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
