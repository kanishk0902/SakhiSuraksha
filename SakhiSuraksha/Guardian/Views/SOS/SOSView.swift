//
//  SOSView.swift
//  Guardian
//
//  The dedicated emergency screen. Extremely clear and usable under stress.
//  High-impact actions (dialing emergency services) always require explicit
//  confirmation and are never automatic.
//

import SwiftUI
import SwiftData
import CoreLocation

struct SOSView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \EmergencyContact.name) private var contacts: [EmergencyContact]

    @State private var showEvidence = false
    @State private var showGetSafe = false
    @State private var confirmCall = false
    @State private var autoActionsTriggered = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if app.emergency.isSOSActive {
                        activeState
                    } else {
                        holdToSend
                    }
                }
                .padding()
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle(app.emergency.isSOSActive ? "Emergency" : "SOS")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .guardianLeading) {
                    Button("Close") {
                        if app.emergency.isSOSActive {
                            app.resolveSOS()
                        } else {
                            dismiss()
                        }
                    }
                }
                if app.emergency.isSOSActive {
                    ToolbarItem(placement: .guardianTrailing) {
                        Button("I'm Safe Now") {
                            app.resolveSOS()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showEvidence) { EvidenceView() }
            .navigationDestination(isPresented: $showGetSafe) { GetSafeView() }
            .confirmationDialog("Call emergency services?",
                                isPresented: $confirmCall, titleVisibility: .visible) {
                Button("Call now", role: .destructive) {
                    if let url = URL(string: "tel://112") { openURL(url) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This dials your region's emergency number. Only you can place this call.")
            }
        }
        .task(id: app.emergency.isSOSActive) {
            guard app.emergency.isSOSActive, !autoActionsTriggered else {
                if !app.emergency.isSOSActive { autoActionsTriggered = false }
                return
            }
            autoActionsTriggered = true
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, app.emergency.isSOSActive else { return }
            if let loc = app.location.currentLocation,
               app.emergency.microphonePermission == .granted,
               !app.emergency.isRecording {
                app.emergency.startEvidence(kind: .audio, location: loc.coordinate,
                                            safetyState: .emergency, journeyID: nil,
                                            context: modelContext)
            }
            if !contacts.isEmpty { sendEmergencySMS() }
        }
    }

    private var backgroundColor: Color {
        app.emergency.isSOSActive ? GuardianTheme.emergency.opacity(0.08) : Color.clear
    }

    // MARK: Hold to send

    private var holdToSend: some View {
        VStack(spacing: 24) {
            Text("Hold to send an emergency alert with your location to your trusted contacts.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 20)

            HoldToSendButton {
                app.triggerSOS(source: .manual)
            }

            Text("Guardian will not contact emergency services automatically. You stay in control.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            quickActions
        }
    }

    // MARK: Active state

    private var activeState: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(systemName: "sos")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 110, height: 110)
                    .background(GuardianTheme.emergency, in: Circle())
                    .symbolEffect(.pulse)
                Text("EMERGENCY ACTIVE")
                    .font(.title2.weight(.bold))
                if let at = app.emergency.activatedAt {
                    Text("Since \(at.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)

            packetCard
            locationCard
            contactsCard
            quickActions
        }
    }

    private var packetCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 10) {
                GuardianSectionHeader(title: "Emergency Packet", systemImage: "shippingbox.fill")
                if let packet = app.emergency.currentPacket {
                    HStack {
                        Label(packet.deliveryState.title, systemImage: packet.deliveryState.symbol)
                            .foregroundStyle(packet.deliveryState.color)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("via \(app.connectivity.state.title)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(packet.message)
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("TTL \(packet.ttl) · \(packet.hopCount) hops")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Preparing packet…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var locationCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 8) {
                GuardianSectionHeader(title: "Your Location", systemImage: "location.fill")
                if let loc = app.location.currentLocation {
                    let c = loc.coordinate
                    Text(String(format: "%.5f, %.5f", c.latitude, c.longitude))
                        .font(.subheadline.monospacedDigit())
                    Text("https://maps.apple.com/?q=\(c.latitude),\(c.longitude)")
                        .font(.caption).foregroundStyle(GuardianTheme.accent)
                    Text("Live GPS · included in your emergency packet")
                        .font(.caption).foregroundStyle(GuardianTheme.safe)
                } else {
                    Label("Acquiring GPS…", systemImage: "location.slash")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var contactsCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Trusted Contacts", systemImage: "person.2.fill")
                if contacts.isEmpty {
                    Text("Add emergency contacts in Settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(contacts) { contact in
                    HStack {
                        ZStack {
                            Circle().fill(GuardianTheme.accent.opacity(0.18))
                            Text(contact.initials).font(.caption.weight(.bold))
                                .foregroundStyle(GuardianTheme.accent)
                        }
                        .frame(width: 38, height: 38)
                        VStack(alignment: .leading) {
                            Text(contact.name).font(.subheadline.weight(.semibold))
                            Text(contact.phone).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            if let url = URL(string: "tel://\(contact.phone.filter { $0.isNumber || $0 == "+" })") {
                                openURL(url)
                            }
                        } label: {
                            Image(systemName: "phone.fill")
                                .foregroundStyle(GuardianTheme.safe)
                        }
                        .accessibilityLabel("Call \(contact.name)")
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                      spacing: 12) {
                SecondaryActionButton(title: "Share Location via SMS",
                                      systemImage: "location.fill.viewfinder",
                                      tint: GuardianTheme.accent) {
                    sendLocationSMS()
                }
                SecondaryActionButton(title: "Send Emergency SMS",
                                      systemImage: "text.bubble.fill",
                                      tint: GuardianTheme.accent) {
                    sendEmergencySMS()
                }
                SecondaryActionButton(title: "Get Me Somewhere Safe",
                                      systemImage: "shield.lefthalf.filled",
                                      tint: GuardianTheme.safe) {
                    showGetSafe = true
                }
                SecondaryActionButton(title: app.emergency.isRecording ? "Recording…" : "Record Evidence",
                                      systemImage: "record.circle",
                                      tint: app.emergency.isRecording ? GuardianTheme.emergency : GuardianTheme.accent) {
                    showEvidence = true
                }
            }
            PrimaryActionButton(title: "Call Emergency Services", systemImage: "phone.fill",
                                color: GuardianTheme.emergency) {
                confirmCall = true
            }
        }
    }

    private func sendLocationSMS() {
        guard let loc = app.location.currentLocation else { return }
        let c = loc.coordinate
        let body = "📍 My location: https://maps.apple.com/?q=\(c.latitude),\(c.longitude)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let phones = contacts.map { $0.phone.filter { $0.isNumber || $0 == "+" } }.joined(separator: ",")
        if let url = URL(string: "sms:\(phones)&body=\(body)") { openURL(url) }
        Haptics.tap()
    }

    private func sendEmergencySMS() {
        let profile = app.modelContext.flatMap { try? $0.fetch(FetchDescriptor<UserProfile>()).first }
        let name = profile?.name.isEmpty == false ? profile!.name : "Guardian User"
        let locStr: String
        if let loc = app.location.currentLocation {
            locStr = "https://maps.apple.com/?q=\(loc.coordinate.latitude),\(loc.coordinate.longitude)"
        } else {
            locStr = "location unavailable"
        }
        let body = "🚨 EMERGENCY from \(name). I need help. My location: \(locStr). Call me or dial 112."
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let phones = contacts.map { $0.phone.filter { $0.isNumber || $0 == "+" } }.joined(separator: ",")
        if let url = URL(string: "sms:\(phones)&body=\(body)") { openURL(url) }
        Haptics.tap()
    }
}

// MARK: - Hold to send button

private struct HoldToSendButton: View {
    var onSend: () -> Void
    @State private var progress: CGFloat = 0
    @State private var isPressing = false
    private let duration: TimeInterval = 1.2

    var body: some View {
        ZStack {
            Circle()
                .stroke(GuardianTheme.emergency.opacity(0.2), lineWidth: 16)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(GuardianTheme.emergency,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 6) {
                Image(systemName: "sos").font(.system(size: 46, weight: .bold))
                Text(isPressing ? "Keep holding…" : "HOLD TO SEND")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(GuardianTheme.emergency)
        }
        .frame(width: 230, height: 230)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 40) {
            // Completed
            progress = 1
            Haptics.emergency()
            onSend()
        } onPressingChanged: { pressing in
            isPressing = pressing
            if pressing {
                withAnimation(.linear(duration: duration)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }
        .accessibilityLabel("Hold to send SOS")
        .accessibilityHint("Press and hold for just over one second to send an emergency alert")
        .accessibilityAddTraits(.isButton)
    }
}
