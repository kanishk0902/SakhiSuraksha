//
//  SettingsDetailViews.swift
//  Guardian
//
//  Preferences, permissions, offline data, communication, privacy and about
//  pages. Each explains permissions and battery/privacy behavior clearly.
//

import SwiftUI
import SwiftData
import CoreLocation
import UserNotifications

// MARK: - Safety preferences

struct SafetyPreferencesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var risk = app.risk
        Form {
            Section("SOS trigger") {
                Stepper("Tap SOS \(app.sosTapCount) time\(app.sosTapCount > 1 ? "s" : "") to activate",
                        value: Binding(
                            get: { app.sosTapCount },
                            set: { app.sosTapCount = $0 }
                        ), in: 1...5)
                Text(app.sosTapCount == 1
                     ? "One tap opens SOS immediately."
                     : "Tap the SOS button \(app.sosTapCount) times within 1.5 seconds to activate. Prevents accidental triggers.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Check-in escalation") {
                Stepper("Raise caution after \(risk.stepsToCautious) missed check-in\(risk.stepsToCautious > 1 ? "s" : "")",
                        value: $risk.stepsToCautious, in: 1...5)
                Stepper("Raise alert after \(risk.stepsToAlert) missed check-ins",
                        value: $risk.stepsToAlert, in: 2...8)
                Text("A missed check-in only raises your caution level — Guardian never assumes danger and never escalates to emergency automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Passive layer") {
                Label("Retains last location, contacts and offline data", systemImage: "battery.75")
                Label("Uses event-driven signals — minimal battery", systemImage: "leaf.fill")
                Label("No continuous camera or microphone", systemImage: "mic.slash.fill")
                    .font(.callout)
            }
        }
        .navigationTitle("Safety Preferences")
        .inlineNavigationTitle()
    }
}

// MARK: - Location permissions

struct LocationPermissionsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Authorization", value: statusText)
                LabeledContent("GPS fix", value: app.location.currentLocation != nil ? "Live" : "Acquiring…")
                if !app.location.hasPermission {
                    Button("Request Location Access") { app.location.requestPermission() }
                }
            }
            Section("How Guardian uses location") {
                Text("Passive: a light-touch position for nearby safe places and your safety score.")
                Text("Journey / Emergency: continuous updates to detect deviation and share your live location.")
                Text("The compass and cached route work with no internet.")
            }
            .font(.callout)
        }
        .navigationTitle("Location")
        .inlineNavigationTitle()
    }

    private var statusText: String {
        switch app.location.authorizationStatus {
        case .authorizedAlways:    return "Always"
        case .authorizedWhenInUse: return "When in use"
        case .denied:              return "Denied"
        case .restricted:          return "Restricted"
        case .notDetermined:       return "Not set"
        @unknown default:          return "Unknown"
        }
    }
}

// MARK: - Notifications

struct NotificationsSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Authorization", value: statusText)
                if app.notifications.authorization != .authorized {
                    Button("Enable Notifications") {
                        Task { await app.notifications.requestPermission() }
                    }
                }
            }
            Section("Guardian sends") {
                Label("Safety check-ins", systemImage: "hand.wave")
                Label("Route deviation", systemImage: "arrow.triangle.branch")
                Label("Journey nearing ETA", systemImage: "flag.checkered")
                Label("Connectivity changes", systemImage: "wifi")
                Label("Packet delivery", systemImage: "shippingbox")
                Label("Emergency state", systemImage: "sos")
            }
            Section {
                Text("Notifications are calm and privacy-conscious — they never reveal sensitive detail on your lock screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notifications")
        .inlineNavigationTitle()
        .task { await app.notifications.refreshStatus() }
    }

    private var statusText: String {
        switch app.notifications.authorization {
        case .authorized:    return "Enabled"
        case .provisional:   return "Provisional"
        case .denied:        return "Denied"
        case .notDetermined: return "Not set"
        #if os(iOS)
        case .ephemeral:     return "Ephemeral"
        #endif
        @unknown default:    return "Unknown"
        }
    }
}

// MARK: - Offline data

struct OfflineDataView: View {
    @Environment(AppModel.self) private var app
    @Query private var packets: [EmergencyPacket]
    @Query private var evidence: [EmergencyEvidence]

    var body: some View {
        Form {
            Section("Cached for offline use") {
                cacheRow("Safe places", "\(app.safetyData.safePlaces.count)", .cached)
                cacheRow("Incidents", "\(app.safetyData.incidents.count)", .real)
                cacheRow("Cached route", app.journey.isActive ? "1 corridor" : "None", app.journey.isActive ? .cached : .offline)
            }
            Section("Persisted locally (SwiftData)") {
                cacheRow("Emergency packets", "\(packets.count)", .offline)
                cacheRow("Evidence records", "\(evidence.count)", .offline)
            }
            Section {
                Text("Guardian caches only what it needs for the safety experience to continue offline. It does not download unlimited map data.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Offline Data")
        .inlineNavigationTitle()
    }

    private func cacheRow(_ title: String, _ value: String, _ provenance: DataProvenance) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
            ProvenanceBadge(provenance: provenance)
        }
    }
}

// MARK: - Communication

struct CommunicationSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section("Current transport") {
                HStack {
                    Text("Active path")
                    Spacer()
                    ConnectivityChip(state: app.connectivity.state, forced: app.connectivity.isForced)
                }
            }
            Section("Communication hierarchy") {
                hierarchyRow(1, "Internet", "Normal messaging, calls, live sharing", true)
                hierarchyRow(2, "Cellular", "Messaging and location sharing", true)
                hierarchyRow(3, "Nearby peer-to-peer", "Future MultipeerConnectivity / Bluetooth / Wi-Fi", false)
                hierarchyRow(4, "Store-and-forward mesh", "Relay through nearby Guardian devices", false)
                hierarchyRow(5, "Local offline storage", "Queued until a path returns", true)
            }
            Section {
                Text("Guardian never claims a live call works with no path. Peer and mesh transports are architected now and simulated until the hardware transport is enabled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Communication")
        .inlineNavigationTitle()
    }

    private func hierarchyRow(_ n: Int, _ title: String, _ subtitle: String, _ real: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).foregroundStyle(GuardianTheme.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ProvenanceBadge(provenance: real ? .real : .future)
        }
    }
}

// MARK: - Privacy

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: GuardianTheme.cardSpacing) {
                GuardianCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Guardian will never", systemImage: "hand.raised.fill")
                            .font(.headline)
                        promise("Silently record audio or video")
                        promise("Falsely claim emergency services were contacted")
                        promise("Falsely claim a mesh or satellite connection exists")
                        promise("Identify people as criminals using unverified AI")
                    }
                }
                GuardianCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Honest data labels", systemImage: "tag.fill")
                            .font(.headline)
                        ForEach([DataProvenance.real, .simulated, .cached, .offline, .future], id: \.self) { p in
                            HStack {
                                ProvenanceBadge(provenance: p)
                                Text(description(for: p)).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .inlineNavigationTitle()
    }

    private func promise(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.circle.fill").foregroundStyle(GuardianTheme.emergency)
            Text(text).font(.subheadline)
            Spacer()
        }
    }

    private func description(for p: DataProvenance) -> String {
        switch p {
        case .real:      return "Live from a device sensor or network"
        case .simulated: return "Generated for demo — not a real feed"
        case .cached:    return "Stored earlier for offline use"
        case .offline:   return "Held locally until a path returns"
        case .future:    return "Architected now, enabled later"
        }
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 64))
                    .foregroundStyle(GuardianTheme.accent)
                    .padding(.top, 20)
                Text("Guardian").font(.largeTitle.weight(.bold))
                Text("Your safety network, even when the network is gone.")
                    .font(.headline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                GuardianCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("An always-available personal safety layer combining live location, intelligent safety routing, emergency SOS and offline mesh communication.")
                            .font(.subheadline)
                        Divider()
                        LabeledContent("Version", value: "1.0")
                        LabeledContent("Passive layer", value: "Always on")
                    }
                }
            }
            .padding()
        }
        .navigationTitle("About")
        .inlineNavigationTitle()
    }
}
