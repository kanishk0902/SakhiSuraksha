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

    // Pre-activation countdown (between hold-to-send and SOS firing)
    @State private var preCountdown: Int? = nil      // nil = not counting down
    @State private var emergencyNote: String = ""
    @State private var preCountdownTask: Task<Void, Never>?
    private let preCountdownDuration = 10

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if app.emergency.isSOSActive {
                        activeState
                    } else if let seconds = preCountdown {
                        preActivationCountdownView(seconds: seconds)
                    } else {
                        holdToSend
                    }
                }
                .padding()
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .guardianLeading) {
                    Button(app.emergency.isSOSActive ? "Close" : (preCountdown != nil ? "Cancel SOS" : "Close")) {
                        if app.emergency.isSOSActive {
                            app.resolveSOS()
                        } else if preCountdown != nil {
                            cancelPreCountdown()
                        } else {
                            app.showSOSScreen = false
                        }
                    }
                    .foregroundStyle(preCountdown != nil ? GuardianTheme.safe : .primary)
                }
                if app.emergency.isSOSActive {
                    ToolbarItem(placement: .guardianTrailing) {
                        Button("I'm Safe Now") { app.resolveSOS() }
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

    private var navigationTitle: String {
        if app.emergency.isSOSActive { return "Emergency" }
        if preCountdown != nil { return "Sending SOS…" }
        return "SOS"
    }

    // MARK: Pre-activation countdown

    private func preActivationCountdownView(seconds: Int) -> some View {
        VStack(spacing: 24) {
            // Ring countdown
            ZStack {
                Circle()
                    .stroke(GuardianTheme.emergency.opacity(0.2), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(seconds) / CGFloat(preCountdownDuration))
                    .stroke(GuardianTheme.emergency,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: seconds)
                VStack(spacing: 4) {
                    Text("\(seconds)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("sec")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 130, height: 130)

            Text("SOS will activate in \(seconds) seconds")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("An AI call will reach you + your location is sent to your contacts via Telegram.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Optional emergency note
            VStack(alignment: .leading, spacing: 6) {
                Text("Describe what's happening (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. being followed near MG Road…", text: $emergencyNote, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3, reservesSpace: true)
                    .font(.subheadline)
            }

            // Cancel button
            Button {
                cancelPreCountdown()
            } label: {
                Label("Cancel — I'm Safe", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(GuardianTheme.safe, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Text("Tap your phone's back button or the Cancel button above to stop.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    private func startPreActivationCountdown() {
        preCountdown = preCountdownDuration
        emergencyNote = ""
        preCountdownTask?.cancel()
        Haptics.warning()
        preCountdownTask = Task {
            for remaining in stride(from: preCountdownDuration - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                preCountdown = remaining
                if remaining <= 3 { Haptics.tap() }
            }
            guard !Task.isCancelled else { return }
            fireSOS()
        }
    }

    private func cancelPreCountdown() {
        preCountdownTask?.cancel()
        preCountdownTask = nil
        preCountdown = nil
        emergencyNote = ""
        Haptics.success()
    }

    private func fireSOS() {
        preCountdownTask = nil
        preCountdown = nil
        app.emergencyNote = emergencyNote.isEmpty ? nil : emergencyNote
        app.triggerSOS(source: .manual)
    }

    private var backgroundColor: Color {
        app.emergency.isSOSActive ? GuardianTheme.emergency.opacity(0.08) : Color.clear
    }

    // MARK: Idle — tap to start countdown

    private var holdToSend: some View {
        VStack(spacing: 28) {
            Text("Tap SOS to start a 10-second countdown.\nYou can cancel any time before it fires.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 16)

            // Big tap button — no hold required
            Button {
                startPreActivationCountdown()
            } label: {
                ZStack {
                    Circle()
                        .fill(GuardianTheme.emergency)
                        .frame(width: 180, height: 180)
                        .shadow(color: GuardianTheme.emergency.opacity(0.45), radius: 24, y: 8)
                    VStack(spacing: 6) {
                        Image(systemName: "sos")
                            .font(.system(size: 52, weight: .bold))
                        Text("TAP TO SEND")
                            .font(.caption.weight(.bold))
                            .tracking(1.5)
                    }
                    .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tap to send SOS")
            .accessibilityHint("Starts a 10-second countdown before sending the emergency alert")

            Text("A call will come to you + Telegram alert sent.\nYou stay in control — emergency services are not called automatically.")
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

            alertStatusCard
            guardianCard
            packetCard
            locationCard
            contactsCard
            quickActions
        }
    }

    private var alertStatusCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 10) {
                GuardianSectionHeader(title: "Alert Status", systemImage: "bell.badge.fill")
                HStack(spacing: 8) {
                    Image(systemName: app.alerts.callStatus.hasPrefix("Call dispatched") ? "phone.fill" : "phone.slash.fill")
                        .foregroundStyle(app.alerts.callStatus.hasPrefix("Call dispatched") ? GuardianTheme.safe : GuardianTheme.caution)
                    Text(app.alerts.callStatus)
                        .font(.footnote)
                }
                HStack(spacing: 8) {
                    Image(systemName: app.alerts.telegramStatus.contains("sent") ? "paperplane.fill" : "paperplane")
                        .foregroundStyle(app.alerts.telegramStatus.contains("sent") ? GuardianTheme.safe : GuardianTheme.caution)
                    Text(app.alerts.telegramStatus)
                        .font(.footnote)
                }
            }
        }
    }

    /// Additive, alongside the existing alerts — never a substitute for the
    /// 112 call / trusted contacts flow above and below it. Regardless of
    /// what happens here, those keep working exactly as before.
    private var guardianCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 10) {
                GuardianSectionHeader(title: "Community Guardian", systemImage: "person.2.wave.2.fill")
                switch app.guardianService.flowState {
                case .idle:
                    EmptyView()
                case .searching:
                    Label("Searching nearby guardians… (\(Int(app.guardianService.currentSearchRadius))m)",
                          systemImage: "location.magnifyingglass")
                        .font(.footnote).foregroundStyle(.secondary)
                case .found:
                    Label("\(app.guardianService.activeRequests.count) guardian(s) notified",
                          systemImage: "person.2.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                case .responding:
                    Label("A verified Guardian is responding nearby", systemImage: "figure.walk")
                        .font(.footnote.weight(.semibold)).foregroundStyle(GuardianTheme.safe)
                case .assisting:
                    Label("Guardian is assisting", systemImage: "checkmark.shield.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(GuardianTheme.safe)
                case .completed:
                    Label("Guardian assistance completed", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                case .failed:
                    Label("No Guardian available — your other alerts remain active", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if app.guardianService.flowState != .idle {
                    Button("View Details") { app.showCommunityGuardianStatus = true }
                        .font(.footnote.weight(.semibold))
                }
            }
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

