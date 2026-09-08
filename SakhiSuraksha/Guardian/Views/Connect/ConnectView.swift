//
//  ConnectView.swift
//  Guardian
//
//  Guardian Connect: the communication hub. Online it offers messaging and
//  call UIs; offline it prepares text/location/voice packets for queued or mesh
//  delivery. It always shows the real transport and never fakes a live call.
//

import SwiftUI
import SwiftData

struct ConnectView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Query(sort: \EmergencyContact.name) private var contacts: [EmergencyContact]
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GuardianTheme.cardSpacing) {
                    connectionCard
                    callCard
                    conversationCard
                    composer
                    linksCard
                }
                .padding()
            }
            .navigationTitle("Connect")
            .navigationDestination(for: ConnectRoute.self) { route in
                switch route {
                case .mesh:    MeshView()
                case .offline: OfflineSafetyView()
                case .share:   LocationSharingView()
                }
            }

        }
    }

    enum ConnectRoute: Hashable { case mesh, offline, share }

    private var connectionCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Connection", systemImage: app.connectivity.state.symbol)
                        .font(.headline)
                    Spacer()
                    ConnectivityChip(state: app.connectivity.state, forced: app.connectivity.isForced)
                }
                Text(app.connectivity.explanation)
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Priority: Internet → Cellular → Nearby mesh → Local queue")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var callCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Call a Contact", systemImage: "phone.fill")
                if contacts.isEmpty {
                    Text("Add emergency contacts in Settings to call them directly.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(contacts.prefix(3)) { contact in
                        Button {
                            if let url = URL(string: "tel://\(contact.phone.filter { $0.isNumber || $0 == "+" })") {
                                openURL(url)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(GuardianTheme.accent.opacity(0.18))
                                    Text(contact.initials).font(.caption.weight(.bold))
                                        .foregroundStyle(GuardianTheme.accent)
                                }
                                .frame(width: 38, height: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.name).font(.subheadline.weight(.semibold))
                                    Text(contact.phone).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "phone.fill")
                                    .foregroundStyle(GuardianTheme.safe)
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }

    private var conversationCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 10) {
                GuardianSectionHeader(title: "Sent Messages", systemImage: "paperplane.fill")
                if app.comms.messages.isEmpty {
                    Text("Messages you send from Guardian appear here with their delivery status.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(app.comms.messages) { message in
                    MessageBubble(message: message)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message your safety network…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(GuardianTheme.card(.dark).opacity(0.001))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.25)))
            Button {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                // Send via SMS to all contacts if available, else queue via mesh
                if !contacts.isEmpty {
                    let phones = contacts.map { $0.phone.filter { $0.isNumber || $0 == "+" } }.joined(separator: ",")
                    let body = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "sms:\(phones)&body=\(body)") {
                        openURL(url)
                    }
                } else {
                    app.comms.send(.text, body: text,
                                   connectivity: app.displayConnectivity, mesh: app.mesh)
                }
                draft = ""
                Haptics.tap()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(GuardianTheme.accent)
            }
            .accessibilityLabel("Send message")
        }
    }

    private var linksCard: some View {
        VStack(spacing: 12) {
            watchStatusRow
            NavigationLink(value: ConnectRoute.mesh) {
                let peerCount = app.mesh.connectedPeers.count
                let subtitle = peerCount == 0
                    ? (app.mesh.isBrowsing ? "Searching for Guardian peers…" : "Mesh inactive")
                    : "\(peerCount) Guardian peer\(peerCount == 1 ? "" : "s") connected"
                linkRow("Mesh Network", subtitle,
                        "point.3.connected.trianglepath.dotted", GuardianTheme.caution)
            }
            NavigationLink(value: ConnectRoute.offline) {
                linkRow("Offline Safety", "What works with no internet",
                        "wifi.slash", GuardianTheme.alert)
            }
            NavigationLink(value: ConnectRoute.share) {
                linkRow("Share Location", "Live or queued for relay",
                        "location.fill.viewfinder", GuardianTheme.accent)
            }
        }
    }

    private var watchStatusRow: some View {
        GuardianCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "applewatch")
                    .foregroundStyle(app.watch.isReachable ? GuardianTheme.safe : .secondary)
                    .font(.title3).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Watch").font(.subheadline.weight(.semibold))
                    Text(app.watch.statusDescription).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(app.watch.isReachable ? GuardianTheme.safe : Color.secondary.opacity(0.4))
                    .frame(width: 9, height: 9)
            }
        }
    }

    private func linkRow(_ title: String, _ subtitle: String, _ symbol: String, _ tint: Color) -> some View {
        GuardianCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(tint).font(.title3).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: CommMessage

    var body: some View {
        HStack {
            if message.outgoing { Spacer(minLength: 40) }
            VStack(alignment: message.outgoing ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if message.kind != .text {
                        Image(systemName: message.kind == .location ? "location.fill" : "waveform")
                            .font(.caption2)
                    }
                    Text(message.body).font(.subheadline)
                }
                HStack(spacing: 4) {
                    Image(systemName: message.state.symbol).font(.caption2)
                    Text(message.state.title).font(.caption2)
                    Text("· \(message.transport)").font(.caption2)
                }
                .foregroundStyle(message.state.color)
            }
            .padding(10)
            .background((message.outgoing ? GuardianTheme.accent : Color.secondary).opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !message.outgoing { Spacer(minLength: 40) }
        }
    }
}


