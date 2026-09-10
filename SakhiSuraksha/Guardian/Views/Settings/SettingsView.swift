//
//  SettingsView.swift
//  Guardian
//
//  Settings hub: profile, contacts, preferences, permissions, offline data,
//  communication, privacy, about — and the clearly-labeled Demo Mode.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Query private var contacts: [EmergencyContact]
    @Query private var communityGuardians: [CommunityGuardian]

    /// Whether this device has already opted in as a Guardian — once true,
    /// the Community row should go straight to the dashboard (where an
    /// incoming request actually surfaces) instead of back to the onboarding
    /// form, which was the only place GuardianDashboardView was reachable.
    private var isLocalGuardian: Bool {
        communityGuardians.contains { $0.isLocalUser }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Personal") {
                    NavigationLink { ProfileView() } label: {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                    NavigationLink { EmergencyContactsView() } label: {
                        Label {
                            HStack {
                                Text("Emergency Contacts")
                                Spacer()
                                Text("\(contacts.count)").foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.2.fill")
                        }
                    }
                    NavigationLink { SafetyPreferencesView() } label: {
                        Label("Safety Preferences", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink { DiscreetSOSSettingsView() } label: {
                        Label("Discreet SOS", systemImage: "bell.badge.waveform")
                    }
                    NavigationLink { GestureSOSSettingsView() } label: {
                        Label("Gesture SOS", systemImage: "hand.wave.fill")
                    }
                }

                Section("Community") {
                    NavigationLink {
                        if isLocalGuardian {
                            GuardianDashboardView()
                        } else {
                            BecomeGuardianView()
                        }
                    } label: {
                        Label {
                            HStack {
                                Text("Community Guardian")
                                Spacer()
                                if isLocalGuardian {
                                    Text(app.guardianService.incomingRequest != nil ? "Request waiting" : "Active")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(app.guardianService.incomingRequest != nil
                                                        ? GuardianTheme.emergency : .secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "person.2.wave.2.fill")
                        }
                    }
                }

                Section("Permissions") {
                    NavigationLink { LocationPermissionsView() } label: {
                        Label("Location", systemImage: "location.fill")
                    }
                    NavigationLink { NotificationsSettingsView() } label: {
                        Label("Notifications", systemImage: "bell.fill")
                    }
                }

                Section("Data & Communication") {
                    NavigationLink { OfflineDataView() } label: {
                        Label("Offline Data", systemImage: "internaldrive.fill")
                    }
                    NavigationLink { CommunicationSettingsView() } label: {
                        Label("Communication", systemImage: "dot.radiowaves.left.and.right")
                    }
                }

                Section("Trust") {
                    NavigationLink { PrivacyView() } label: {
                        Label("Privacy", systemImage: "hand.raised.fill")
                    }
                    NavigationLink { AboutView() } label: {
                        Label("About Guardian", systemImage: "shield.lefthalf.filled")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
