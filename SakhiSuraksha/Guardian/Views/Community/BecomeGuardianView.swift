//
//  BecomeGuardianView.swift
//  Guardian
//
//  Opt-in onboarding for Community Guardian, and the availability toggle once
//  opted in. No verification backend exists yet — every level is honestly
//  labeled as prototype/demo verification (GuardianVerificationLevel.label),
//  never claimed as real-world certification. Mirrors DiscreetSOSSettingsView's
//  single-Form, load/save pattern.
//
//  IMPORTANT — real range: matching runs over MultipeerConnectivity
//  (Bluetooth/WiFi Direct), not a server. There is no backend, so a Guardian
//  can only ever be reached while they are within real physical range (same
//  room/building — tens of meters, not a neighborhood) with the app open.
//  Copy in this screen must never imply a wider radius than that.
//

import SwiftUI
import SwiftData
import CoreLocation

struct BecomeGuardianView: View {
    @Environment(AppModel.self) private var app
    @Query private var localGuardians: [CommunityGuardian]

    @State private var displayName: String = ""
    @State private var level: GuardianVerificationLevel = .community
    @State private var capabilities: Set<GuardianCapability> = []
    @State private var isAvailable = false

    private var localGuardian: CommunityGuardian? {
        localGuardians.first { $0.isLocalUser }
    }

    var body: some View {
        Form {
            Section {
                Text("Community Guardian lets opted-in people who are physically very close by — the same room, home, or building, like a hostel, apartment block, or office — offer non-confrontational assistance during someone's SOS, while professional emergency services remain the primary response. You will only ever be shown requests routed to you for an active emergency, never a list of nearby people.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Label("Works over direct phone-to-phone connection, not the internet — Guardians must be within about 100 meters with the app open to be reachable.", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Your Guardian Profile") {
                TextField("Display name shown to requesters", text: $displayName)
                Picker("Verification level", selection: $level) {
                    ForEach(GuardianVerificationLevel.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
                Text(level.label)
                    .font(.caption)
                    .foregroundStyle(GuardianTheme.caution)
            }

            Section("Capabilities") {
                ForEach(GuardianCapability.allCases) { capability in
                    Button {
                        toggle(capability)
                    } label: {
                        HStack {
                            Image(systemName: capability.symbol)
                                .frame(width: 24)
                                .foregroundStyle(GuardianTheme.accent)
                            Text(capability.title)
                            Spacer()
                            if capabilities.contains(capability) {
                                Image(systemName: "checkmark").foregroundStyle(GuardianTheme.safe)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }

            Section("Safety First") {
                Label("Assist, don't confront.", systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                Text("You may call emergency services, stay at a safe distance, guide someone to a Safe Haven, alert security, or provide first aid if trained. Never fight, chase, or physically intervene.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if localGuardian != nil {
                Section("Availability") {
                    Toggle("Available to assist right now", isOn: $isAvailable)
                        .onChange(of: isAvailable) { _, newValue in
                            app.guardianService.setAvailability(
                                newValue ? .available : .offline,
                                location: newValue ? app.location.currentLocation?.coordinate : nil)
                        }
                    if isAvailable {
                        Text("Only reachable while Guardian is open on your phone and you're within about 100m of someone's emergency. Your approximate distance is only shared if you're matched to an active emergency.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink("Guardian Dashboard") { GuardianDashboardView() }
                }
            }

            Section {
                Button(localGuardian == nil ? "Become a Guardian" : "Save Changes") { save() }
                    .fontWeight(.semibold)
                    .disabled(displayName.isEmpty || capabilities.isEmpty)
            }
        }
        .navigationTitle("Community Guardian")
        .inlineNavigationTitle()
        .onAppear(perform: load)
    }

    private func toggle(_ capability: GuardianCapability) {
        if capabilities.contains(capability) {
            capabilities.remove(capability)
        } else {
            capabilities.insert(capability)
        }
    }

    private func load() {
        guard let guardian = localGuardian else { return }
        displayName = guardian.displayName
        level = guardian.verificationLevel
        capabilities = Set(guardian.capabilities)
        isAvailable = guardian.availability == .available
    }

    private func save() {
        app.guardianService.becomeGuardian(displayName: displayName, level: level,
                                           capabilities: Array(capabilities))
        Haptics.success()
    }
}
