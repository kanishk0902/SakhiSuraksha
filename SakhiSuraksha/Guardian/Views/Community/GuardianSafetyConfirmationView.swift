//
//  GuardianSafetyConfirmationView.swift
//  Guardian
//
//  Shown once, immediately after a Guardian accepts a request — explicit
//  allowed/forbidden actions so "assist, don't confront" is never ambiguous.
//  Local to GuardianDashboardView's flow; not promoted to a global AppModel
//  flag since nothing else needs to present it.
//

import SwiftUI

struct GuardianSafetyConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    var onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(GuardianTheme.caution)
                        Text("Safety First")
                            .font(.title2.weight(.bold))
                        Text("Only proceed if you can assist safely.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    GuardianCard {
                        VStack(alignment: .leading, spacing: 12) {
                            GuardianSectionHeader(title: "You may", systemImage: "checkmark.circle.fill")
                            bullet("Contact emergency services")
                            bullet("Stay at a safe distance")
                            bullet("Help the person reach a Safe Haven")
                            bullet("Alert nearby security")
                            bullet("Provide first aid if appropriately trained")
                            bullet("Stay on the phone with them")
                        }
                    }

                    GuardianCard {
                        VStack(alignment: .leading, spacing: 12) {
                            GuardianSectionHeader(title: "Never", systemImage: "xmark.octagon.fill")
                            bullet("Fight or confront an attacker", color: GuardianTheme.emergency)
                            bullet("Chase anyone", color: GuardianTheme.emergency)
                            bullet("Physically intervene", color: GuardianTheme.emergency)
                            bullet("Put yourself in unnecessary danger", color: GuardianTheme.emergency)
                        }
                    }

                    PrimaryActionButton(title: "I Can Assist Safely", systemImage: "checkmark.shield.fill",
                                        color: GuardianTheme.safe) {
                        onConfirm()
                        dismiss()
                    }
                }
                .padding()
            }
            .navigationTitle("Community Guardian")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .guardianLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func bullet(_ text: String, color: Color = GuardianTheme.safe) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .padding(.top, 6)
                .foregroundStyle(color)
            Text(text).font(.subheadline)
        }
    }
}
