//
//  NearbyResultsSection.swift
//  Guardian
//
//  Shared results list for any screen backed by NearbyPlacesService — used by
//  I Need Help, Period Emergency, and Safe Havens so each doesn't duplicate
//  the same row/loading/empty-state layout.
//

import SwiftUI

struct NearbyResultsSection: View {
    let service: NearbyPlacesService
    var onWiderSearch: (() -> Void)? = nil

    var body: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: service.lastQuery?.displayName ?? "Nearby",
                                      systemImage: "mappin.and.ellipse")
                if service.isSearching {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Searching nearby…").font(.footnote).foregroundStyle(.secondary)
                    }
                } else if let error = service.errorMessage, service.results.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                        if let onWiderSearch {
                            Button("Search a wider area") { onWiderSearch() }
                                .font(.footnote.weight(.semibold))
                        }
                    }
                } else {
                    ForEach(service.results) { place in
                        row(place)
                        if place.id != service.results.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func row(_ place: NearbyPlace) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.subheadline.weight(.semibold))
                Text("\(place.distanceText)\(place.address.isEmpty ? "" : " · \(place.address)")")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if place.phone != nil {
                Button { service.call(place) } label: {
                    Image(systemName: "phone.fill").foregroundStyle(GuardianTheme.safe)
                }
                .accessibilityLabel("Call \(place.name)")
            }
            Button { service.openInMaps(place) } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .foregroundStyle(GuardianTheme.accent)
            }
            .accessibilityLabel("Directions to \(place.name)")
        }
    }
}
