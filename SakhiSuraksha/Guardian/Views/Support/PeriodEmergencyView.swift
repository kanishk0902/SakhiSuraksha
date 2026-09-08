//
//  PeriodEmergencyView.swift
//  Guardian
//
//  Not a period tracker — assistance for unexpected menstrual needs. Grid of
//  PeriodNeedType, each routing to a nearby-places search or a contact-based
//  assistance request.
//

import SwiftUI
import CoreLocation

struct PeriodEmergencyView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var nearby = NearbyPlacesService()
    @State private var selected: PeriodNeedType?
    @State private var showRequestAssistance = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GuardianTheme.cardSpacing) {
                    GuardianCard {
                        Text("I need help with…")
                            .font(.headline)
                    }
                    OptionRowList(data: PeriodNeedType.allCases) { need in
                        OptionRow(title: need.title, systemImage: need.symbol,
                                 tint: GuardianTheme.accent, isSelected: selected == need) {
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
            .navigationTitle("Period Emergency")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showRequestAssistance) {
                RequestAssistanceSheet(needType: selected?.title ?? "Menstrual assistance")
            }
        }
    }

    private func handle(_ need: PeriodNeedType) {
        selected = need
        Haptics.tap()
        switch need {
        case .pads, .tampons, .pharmacy, .hygiene: search(.pharmacy)
        case .washroom:                            search(.restroom)
        case .water:                               search(.custom("water"))
        case .requestAssistance:                   showRequestAssistance = true
        }
    }

    private func search(_ query: NearbyPlaceQuery) {
        let coord = app.location.currentLocation?.coordinate ?? LocationService.fallbackCoordinate
        Task { await nearby.search(for: query, near: coord) }
    }
}
