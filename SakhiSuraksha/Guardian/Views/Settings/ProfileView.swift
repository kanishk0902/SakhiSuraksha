//
//  ProfileView.swift
//  Guardian
//
//  Edit the user profile and the emergency message shared during an SOS.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        Form {
            if let profile {
                Section("You") {
                    TextField("Name", text: Binding(
                        get: { profile.name },
                        set: { profile.name = $0; save() }))
                    TextField("Blood type (optional)", text: Binding(
                        get: { profile.bloodType },
                        set: { profile.bloodType = $0; save() }))
                }
                Section("Medical") {
                    TextField("Medical notes (optional)", text: Binding(
                        get: { profile.medicalNotes },
                        set: { profile.medicalNotes = $0; save() }), axis: .vertical)
                    Toggle("Share medical info in an emergency", isOn: Binding(
                        get: { profile.shareMedicalInEmergency },
                        set: { profile.shareMedicalInEmergency = $0; save() }))
                }
                Section("Emergency message") {
                    TextField("Message sent with SOS", text: Binding(
                        get: { profile.emergencyMessage },
                        set: { profile.emergencyMessage = $0; save() }), axis: .vertical)
                    Text("This message is included in your emergency packet along with your location.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Profile unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
            }
        }
        .navigationTitle("Profile")
        .inlineNavigationTitle()
    }

    private func save() { try? context.save() }
}
