//
//  CompassView.swift
//  Guardian
//
//  A dedicated compass that works fully offline (device heading is a sensor).
//  Points toward a selected safe place and shows distance + relative bearing.
//

import SwiftUI
import CoreLocation
import MapKit

struct CompassView: View {
    @Environment(AppModel.self) private var app
    var target: SafePlace?

    @State private var selected: SafePlace?

    private var activeTarget: SafePlace? { target ?? selected }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                compassDial
                if let activeTarget {
                    targetCard(activeTarget)
                } else {
                    picker
                }
                offlineNote
            }
            .padding()
        }
        .navigationTitle("Compass")
        .inlineNavigationTitle()
        .onAppear { app.location.startHeading() }
        .onDisappear { if !app.journey.isActive { app.location.stopHeading() } }
    }

    // MARK: Dial

    private var compassDial: some View {
        let heading = app.location.heading
        let bearing = activeTarget.map { app.location.bearing(to: $0.coordinate) }
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
            ForEach(0..<12) { i in
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 2, height: i % 3 == 0 ? 16 : 8)
                    .offset(y: -125)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            // North indicator rotates opposite to heading.
            VStack {
                Image(systemName: "location.north.fill")
                    .font(.title)
                    .foregroundStyle(GuardianTheme.emergency)
                Spacer()
            }
            .rotationEffect(.degrees(-heading))
            .frame(height: 250)

            // Bearing to target.
            if let bearing {
                VStack {
                    Image(systemName: "arrowshape.up.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(GuardianTheme.safe)
                    Spacer()
                }
                .rotationEffect(.degrees(bearing - heading))
                .frame(height: 250)
                .animation(.easeInOut(duration: 0.3), value: heading)
            }

            VStack(spacing: 2) {
                Text("\(Int(heading))°")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(cardinal(for: heading))
                    .font(.headline).foregroundStyle(.secondary)
            }
        }
        .frame(width: 280, height: 280)
        .accessibilityLabel("Heading \(Int(heading)) degrees, \(cardinal(for: heading))")
    }

    private func targetCard(_ place: SafePlace) -> some View {
        let loc = app.location.currentLocation ?? CLLocation()
        let distance = place.distance(from: loc)
        return GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(place.name, systemImage: place.type.symbol)
                        .font(.headline)
                    Spacer()
                    if target == nil {
                        Button("Change") { selected = nil }
                            .font(.caption)
                    }
                }
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text(distance < 1000 ? "\(Int(distance)) m"
                             : String(format: "%.1f km", distance / 1000))
                            .font(.title3.weight(.bold))
                        Text("Distance").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading) {
                        Text("\(Int(app.location.bearing(to: place.coordinate)))°")
                            .font(.title3.weight(.bold))
                        Text("Bearing").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Follow the green arrow to walk toward \(place.name).")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
                    item.name = place.name
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                } label: {
                    Label("Navigate in Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(GuardianTheme.accent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var picker: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Navigate to a safe place",
                                      systemImage: "shield.lefthalf.filled")
                ForEach(app.safetyData.safePlaces.prefix(5)) { place in
                    Button { selected = place } label: {
                        HStack {
                            SafePlaceRow(place: place)
                            Image(systemName: "chevron.right").font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    private var offlineNote: some View {
        Label("The compass uses the device magnetometer and works with no internet.",
              systemImage: "wifi.slash")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cardinal(for heading: CLLocationDirection) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((heading + 22.5) / 45) % 8
        return dirs[max(0, index)]
    }
}
