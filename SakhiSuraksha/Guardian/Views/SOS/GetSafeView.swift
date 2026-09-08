//
//  GetSafeView.swift
//  Guardian
//
//  "Get Me Somewhere Safe" — finds and ranks the best nearby safe destination
//  and offers online (Apple Maps) or offline (compass) navigation.
//

import SwiftUI
import MapKit

struct GetSafeView: View {
    @Environment(AppModel.self) private var app
    @State private var compassTarget: SafePlace?

    private var destinations: [SafeDestination] {
        let loc = app.location.currentLocation ?? CLLocation()
        return app.safetyData.rankedDestinations(from: loc,
                                                  safetyConfidence: app.confidence.score)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GuardianTheme.cardSpacing) {
                if let best = destinations.first {
                    bestCard(best)
                }
                if destinations.count > 1 {
                    alternativesCard
                }
                explanationCard
            }
            .padding()
        }
        .navigationTitle("Get Me Somewhere Safe")
        .inlineNavigationTitle()
        .navigationDestination(item: $compassTarget) { place in
            CompassView(target: place)
        }
    }

    private func bestCard(_ dest: SafeDestination) -> some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(dest.place.type.title.uppercased(), systemImage: dest.place.type.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(dest.place.type.tint)
                    Spacer()
                    ProvenanceBadge(provenance: dest.place.provenance)
                }
                Text(dest.place.name)
                    .font(.title2.weight(.bold))
                HStack(spacing: 20) {
                    metric("Distance", dest.distanceText, "figure.walk")
                    metric("Safety Score", "\(dest.place.safetyScore)", "shield.fill")
                    metric("Match", "\(dest.rankedScore)", "sparkles")
                }
                HStack(spacing: 12) {
                    PrimaryActionButton(title: "Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                                        color: GuardianTheme.accent) {
                        navigate(to: dest.place)
                    }
                    Button {
                        compassTarget = dest.place
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "location.north.line.fill")
                            Text("Compass").font(.headline)
                        }
                        .guardianCapsule(GuardianTheme.safe)
                    }
                    .buttonStyle(PressableStyle())
                }
                if !app.connectivity.state.hasInternet {
                    Label("Offline — use Compass to walk there", systemImage: "wifi.slash")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(GuardianTheme.accent)
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var alternativesCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Alternatives", systemImage: "list.bullet")
                ForEach(destinations.dropFirst()) { dest in
                    Button {
                        navigate(to: dest.place)
                    } label: {
                        HStack {
                            SafePlaceRow(place: dest.place, distance: dest.distance)
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    if dest.id != destinations.last?.id { Divider() }
                }
            }
        }
    }

    private var explanationCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("How ranking works", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                Text("Places are fetched live from Apple Maps around your current location. They're ranked by walking distance, place type (police and hospitals rank highest in emergencies), and safety score.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func navigate(to place: SafePlace) {
        Haptics.tap()
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        item.name = place.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}
