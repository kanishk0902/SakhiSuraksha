//
//  SafeHavensView.swift
//  Guardian
//
//  A Safe Haven is a nearby place to go if you feel unsafe or need basic
//  assistance. Two honestly-separated sections:
//   - Nearby (MapKit): real search results, never labeled "Verified" — a
//     pharmacy returned by MapKit is not vetted by anyone.
//   - Verified (SupportResourcesService): only entries our own service
//     actually marks isVerified == true.
//

import SwiftUI
import CoreLocation

struct SafeHavensView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var nearby = NearbyPlacesService()
    @State private var selectedType: SafeHavenType = .pharmacy

    private let mapKitTypes: [(SafeHavenType, NearbyPlaceQuery)] = [
        (.pharmacy, .pharmacy),
        (.hospital, .hospital),
        (.policeStation, .policeStation),
        (.cafe, .cafe),
        (.restaurant, .custom("restaurant")),
        (.shop, .custom("shop")),
        (.college, .custom("college")),
        (.petrolPump, .petrolPump),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GuardianTheme.cardSpacing) {
                    introCard
                    typePicker
                    NearbyResultsSection(service: nearby) {
                        Task { await nearby.searchWider() }
                    }
                    if let first = nearby.results.first {
                        ShareDestinationButton(destinationName: first.name, coordinate: first.coordinate)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    verifiedSection
                }
                .padding()
            }
            .navigationTitle("Safe Havens")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await search(for: selectedType) }
        }
    }

    private var introCard: some View {
        GuardianCard {
            Label("A safe place to go if you feel unsafe or need help — water, first aid, or somewhere to wait.",
                  systemImage: "storefront.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var typePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(mapKitTypes, id: \.0) { type, _ in
                    Button {
                        selectedType = type
                        Task { await search(for: type) }
                    } label: {
                        Label(type.title, systemImage: type.symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(selectedType == type ? GuardianTheme.accent : Color.secondary.opacity(0.15))
                            .foregroundStyle(selectedType == type ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var verifiedSection: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Verified Organisations", systemImage: "checkmark.seal.fill")
                if app.support.helplines.isEmpty {
                    Text("Verified local organisations will appear here once available.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(app.support.helplines) { resource in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(resource.name).font(.subheadline.weight(.semibold))
                                    Label("Verified", systemImage: "checkmark.seal.fill")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(GuardianTheme.safe)
                                }
                                Text(resource.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if resource.phone != nil {
                                Button { app.support.call(resource) } label: {
                                    Image(systemName: "phone.fill").foregroundStyle(GuardianTheme.safe)
                                }
                            }
                        }
                        if resource.id != app.support.helplines.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func search(for type: SafeHavenType) async {
        guard let query = mapKitTypes.first(where: { $0.0 == type })?.1 else { return }
        let coord = app.location.currentLocation?.coordinate ?? LocationService.fallbackCoordinate
        await nearby.search(for: query, near: coord)
    }
}
