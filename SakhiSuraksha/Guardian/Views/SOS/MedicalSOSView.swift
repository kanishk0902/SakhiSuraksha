//
//  MedicalSOSView.swift
//  Guardian
//

import SwiftUI
import SwiftData
import MapKit

struct MedicalSOSView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selected: MedicalEmergencyType?
    @State private var confirmed = false
    @State private var nearbyService = NearbyPlacesService()
    @State private var showPregnancyDetail = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if confirmed, let type = selected {
                        activeView(type)
                    } else {
                        selectionView
                    }
                }
                .padding()
            }
            .navigationTitle("Medical SOS")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: Selection

    private var selectionView: some View {
        VStack(spacing: 16) {
            GuardianCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Select your emergency", systemImage: "cross.case.fill")
                        .font(.headline)
                    Text("This will notify your trusted contacts and show nearby medical facilities. Guardian does not diagnose.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                      spacing: 12) {
                ForEach(MedicalEmergencyType.allCases, id: \.self) { type in
                    Button {
                        selected = type
                        if type == .pregnancyEmergency {
                            showPregnancyDetail = true
                        } else {
                            confirm(type)
                        }
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: type.symbol)
                                .font(.title2)
                                .foregroundStyle(type.color)
                            Text(type.title)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 90)
                        .background(type.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            PrimaryActionButton(title: "Call Ambulance — 108",
                                systemImage: "phone.fill",
                                color: GuardianTheme.emergency) {
                if let ambulance = app.support.helplines.first(where: { $0.phone == "108" }) {
                    app.support.call(ambulance)
                }
            }
        }
        .sheet(isPresented: $showPregnancyDetail) {
            PregnancyEmergencySheet { confirm(.pregnancyEmergency) }
        }
    }

    // MARK: Active

    private func activeView(_ type: MedicalEmergencyType) -> some View {
        VStack(spacing: 16) {
            GuardianCard {
                VStack(spacing: 12) {
                    HStack(spacing: 14) {
                        Image(systemName: type.symbol)
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(type.color, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Medical emergency selected")
                                .font(.headline)
                            Text(type.title)
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("Trusted contacts notified · Location captured")
                                .font(.caption).foregroundStyle(GuardianTheme.safe)
                        }
                        Spacer()
                    }
                }
            }

            // Emergency calls
            GuardianCard {
                VStack(spacing: 12) {
                    GuardianSectionHeader(title: "Emergency Calls", systemImage: "phone.fill")
                    ForEach(app.support.nearestHelplines().filter { ["108", "112", "181"].contains($0.phone) }) { resource in
                        callButton("\(resource.name) — \(resource.phone ?? "")", resource: resource)
                        if resource.id != app.support.helplines.last?.id { Divider() }
                    }
                }
            }

            // Nearby hospitals
            if nearbyService.isSearching {
                ProgressView("Finding nearby hospitals…")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if !nearbyService.results.isEmpty {
                nearbyHospitalsCard
            }

            PrimaryActionButton(title: "I'm Safe Now",
                                systemImage: "checkmark.circle.fill",
                                color: GuardianTheme.safe) {
                dismiss()
            }
        }
    }

    private var nearbyHospitalsCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Nearest Hospitals", systemImage: "cross.fill")
                ForEach(nearbyService.results.prefix(3)) { place in
                    Button {
                        nearbyService.openInMaps(place)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).font(.subheadline.weight(.semibold))
                                Text(place.distanceText).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .foregroundStyle(GuardianTheme.accent)
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    if place.id != nearbyService.results.prefix(3).last?.id { Divider() }
                }
            }
        }
    }

    private func callButton(_ label: String, resource: SupportResource) -> some View {
        Button {
            app.support.call(resource)
        } label: {
            HStack {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "phone.fill").foregroundStyle(GuardianTheme.emergency)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func confirm(_ type: MedicalEmergencyType) {
        selected = type
        confirmed = true
        Haptics.emergency()

        let coord = app.location.currentLocation?.coordinate ?? LocationService.fallbackCoordinate
        let event = MedicalSOSEvent(emergencyType: type,
                                    latitude: coord.latitude,
                                    longitude: coord.longitude)
        context.insert(event)
        try? context.save()

        app.beginSOSCountdown(source: .medicalSOS,
                              message: "Medical emergency: \(type.title). I need help.")

        Task {
            await nearbyService.search(for: .hospital, near: coord)
        }
    }
}

// MARK: - Pregnancy detail sheet

private struct PregnancyEmergencySheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: () -> Void

    private let options = [
        "Labor / sudden severe pain",
        "Water broke",
        "Heavy bleeding",
        "Feeling faint",
        "Other pregnancy emergency"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Select what best describes your situation. Guardian will not diagnose — this helps notify your contacts.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(options, id: \.self) { option in
                    Button {
                        dismiss()
                        onConfirm()
                    } label: {
                        Label(option, systemImage: "figure.2.and.child.holdinghands")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Pregnancy Emergency")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
            }
        }
    }
}
