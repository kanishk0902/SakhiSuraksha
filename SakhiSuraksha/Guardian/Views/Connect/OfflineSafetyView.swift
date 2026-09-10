//
//  OfflineSafetyView.swift
//  Guardian
//
//  Clearly communicates what remains available with zero internet. Guardian
//  never claims cloud communication when there is none.
//

import SwiftUI
import SwiftData

struct OfflineSafetyView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(spacing: GuardianTheme.cardSpacing) {
                headerCard
                availabilityCard
                actionsCard
            }
            .padding()
        }
        .navigationTitle("Offline Safety")
        .inlineNavigationTitle()
    }

    private var isOffline: Bool { !app.connectivity.state.hasInternet }

    private var headerCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: isOffline ? "wifi.slash" : "wifi")
                        .font(.title)
                        .foregroundStyle(isOffline ? GuardianTheme.alert : GuardianTheme.safe)
                    VStack(alignment: .leading) {
                        Text(isOffline ? "No internet connection" : "You're online")
                            .font(.headline)
                        Text(isOffline ? "Guardian is running locally."
                             : "Everything below also works offline.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private var availabilityCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Available Offline", systemImage: "checklist")
                AvailabilityRow(title: "Location (GPS)", available: true)
                Divider()
                AvailabilityRow(title: "Cached Route", available: app.journey.isActive)
                Divider()
                AvailabilityRow(title: "Compass", available: true)
                Divider()
                AvailabilityRow(title: "Safe Places", available: !app.safetyData.safePlaces.isEmpty)
                Divider()
                AvailabilityRow(title: "Emergency Contacts", available: true)
                Divider()
                AvailabilityRow(title: "Emergency Packet", available: true)
                Divider()
                AvailabilityRow(title: "Mesh Relay", available: !app.mesh.connectedPeers.isEmpty)
                Divider()
                AvailabilityRow(title: "Live Calls / Cloud Sync", available: !isOffline)
            }
        }
    }

    private var actionsCard: some View {
        VStack(spacing: 12) {
            PrimaryActionButton(title: "Send SOS Emergency Packet",
                                systemImage: "shippingbox.fill",
                                color: GuardianTheme.emergency) {
                app.beginSOSCountdown()
            }
            Text("Packets are stored locally and relay automatically when a mesh peer or internet path returns.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
