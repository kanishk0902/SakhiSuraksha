//
//  INeedHelpView.swift
//  Guardian
//
//  Everyday, not-necessarily-emergency needs. Grid of HelpNeedType, each
//  routing to a nearby-places search, another support screen, or an SOS/
//  request-assistance escalation.
//

import SwiftUI
import CoreLocation

struct INeedHelpView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var nearby = NearbyPlacesService()
    @State private var selected: HelpNeedType?
    @State private var showSafeHavens = false
    @State private var showRequestAssistance = false
    @State private var confirmUnsafe = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GuardianTheme.cardSpacing) {
                    GuardianCard {
                        Label("Pick what you need — this isn't necessarily an emergency.",
                              systemImage: "hand.raised.fill")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    OptionRowList(data: HelpNeedType.allCases) { need in
                        OptionRow(title: need.title, systemImage: need.symbol,
                                 tint: need.color, isSelected: selected == need) {
                            handle(need)
                        }
                    }
                    if selected != nil, !nearby.results.isEmpty || nearby.isSearching || nearby.errorMessage != nil {
                        NearbyResultsSection(service: nearby) {
                            Task { await nearby.searchWider() }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("I Need Help")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showSafeHavens) { SafeHavensView() }
            .sheet(isPresented: $showRequestAssistance) {
                RequestAssistanceSheet(needType: selected?.title ?? "Assistance")
            }
            .confirmationDialog("Send an SOS alert?", isPresented: $confirmUnsafe, titleVisibility: .visible) {
                Button("Send SOS", role: .destructive) {
                    app.beginSOSCountdown(source: .manual, message: "I feel unsafe. I need help.")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This shares your location with your trusted contacts.")
            }
        }
    }

    private func handle(_ need: HelpNeedType) {
        selected = need
        Haptics.tap()
        switch need {
        case .periodSupplies: search(.pharmacy)
        case .washroom:       search(.restroom)
        case .water:          search(.custom("water"))
        case .firstAid:       search(.pharmacy)
        case .medicine:       search(.pharmacy)
        case .medicalHelp:    search(.hospital)
        case .transport:      search(.custom("taxi stand"))
        case .feelingUnsafe:  confirmUnsafe = true
        case .accompaniment:  showRequestAssistance = true
        case .safeHaven:      showSafeHavens = true
        }
    }

    private func search(_ query: NearbyPlaceQuery) {
        let coord = app.location.currentLocation?.coordinate ?? LocationService.fallbackCoordinate
        Task { await nearby.search(for: query, near: coord) }
    }
}
