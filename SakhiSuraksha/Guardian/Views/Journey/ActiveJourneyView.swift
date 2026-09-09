//
//  ActiveJourneyView.swift
//  Guardian
//
//  The live journey: map, position, route, ETA, progress, safety confidence,
//  connectivity, nearby safe places, and conservative deviation prompts.
//

import SwiftUI
import MapKit
import SwiftData

struct ActiveJourneyView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var showEndConfirm = false
    @State private var showGetSafe = false
    @State private var showActiveNavigation = false
    /// Per-route safety colours scored when the journey starts. Empty until scoring completes.
    @State private var routeColors: [Color] = []

    var body: some View {
        Group {
            if let journey = app.journey.active {
                ScrollView {
                    VStack(spacing: GuardianTheme.cardSpacing) {
                        mapCard(journey)
                        PrimaryActionButton(title: "Start Navigation", systemImage: "location.north.line.fill",
                                            color: GuardianTheme.accent) {
                            showActiveNavigation = true
                        }
                        if journey.deviation.severity() >= DeviationLevel.cautious.severity() {
                            deviationCard
                        }
                        statusCard(journey)
                        checkpointsCard(journey)
                        nearbyCard(journey)
                        endButton
                    }
                    .padding()
                }
                .task(id: journey.id) { await scoreRoutes(journey) }
            } else {
                ContentUnavailableView("No active journey", systemImage: "figure.walk")
            }
        }
        .confirmationDialog("End this journey?", isPresented: $showEndConfirm,
                            titleVisibility: .visible) {
            Button("I've arrived safely") { endJourney(completed: true) }
            Button("Cancel journey", role: .destructive) { endJourney(completed: false) }
            Button("Keep going", role: .cancel) {}
        }
        .navigationDestination(isPresented: $showGetSafe) { GetSafeView() }
        .navigationDestination(isPresented: $showActiveNavigation) { ActiveNavigationView() }
    }

    private func scoreRoutes(_ journey: LiveJourney) async {
        let all = [journey.corridor.routeCoordinates] + journey.corridor.alternateRoutes
        guard all.count > 1 else { routeColors = []; return }
        let provider = LocalRouteSafetyProvider(data: app.safetyData)
        var scores: [Int] = []
        for route in all {
            let s = (try? await provider.safetyScore(for: route)) ?? 50
            scores.append(s)
        }
        // Normalize across routes so they always span green/yellow/red.
        // Relative rank (best vs worst route) is what matters for the user.
        let minS = scores.min() ?? 50
        let maxS = scores.max() ?? 50
        let normalized: [Int]
        if maxS - minS < 5 {
            // Routes nearly identical score-wise → force colour spread by index
            normalized = scores.indices.map { i in max(30, 90 - i * 25) }
        } else {
            normalized = scores.map { s in
                Int(30.0 + Double(s - minS) / Double(maxS - minS) * 60.0)
            }
        }
        routeColors = normalized.map { routeColor(score: $0) }
    }

    private func routeColor(score: Int) -> Color {
        if score >= 65 { return GuardianTheme.safe }
        if score >= 40 { return Color.orange }
        return GuardianTheme.emergency
    }

    // MARK: Map

    private func mapCard(_ journey: LiveJourney) -> some View {
        let allRoutes = [journey.corridor.routeCoordinates] + journey.corridor.alternateRoutes
        let colors: [Color]? = routeColors.count == allRoutes.count ? routeColors : nil
        return GuardianMap(routes: allRoutes,
                    routeColors: colors,
                    safePlaces: journey.corridor.nearbySafePlaces,
                    incidents: journey.corridor.incidents,
                    cctv: journey.corridor.cctv,
                    zones: journey.corridor.zones,
                    checkpoints: journey.corridor.checkpoints,
                    destination: journey.destination,
                    userPosition: app.location.currentLocation?.coordinate,
                    userHeading: navigationHeading,
                    minimalOverlays: true,
                    fitsRouteOnAppear: true)
            .frame(height: 480)
            .clipShape(RoundedRectangle(cornerRadius: GuardianTheme.cornerRadius, style: .continuous))
            // Turn-by-turn banner overlaid at the top — like Apple Maps navigation
            .overlay(alignment: .top) {
                if let step = journey.currentStep {
                    TurnBanner(step: step, distanceMeters: journey.distanceToNextStepMeters)
                        .padding(12)
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 12).padding(.top, 12)
                }
            }
            .overlay(alignment: .topLeading) {
                if journey.currentStep == nil {
                    HStack(spacing: 8) {
                        ProvenanceBadge(provenance: journey.routeProvenance)
                        Text("Safety Corridor active")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(10)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let nearest = nearestSafePlace(journey) {
                    nearestSafePlaceCallout(nearest)
                        .padding(10)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if colors != nil {
                    routeLegend
                        .padding(10)
                }
            }
    }

    private var routeLegend: some View {
        VStack(alignment: .trailing, spacing: 4) {
            legendDot(GuardianTheme.safe, "Safest")
            legendDot(.orange, "Moderate")
            legendDot(GuardianTheme.emergency, "Avoid")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2.weight(.semibold))
            Circle().fill(color).frame(width: 10, height: 10)
        }
    }

    private var navigationHeading: CLLocationDirection? {
        app.location.navigationHeading(fallbackBearingTo: app.journey.active?.destination)
    }

    private func nearestSafePlace(_ journey: LiveJourney) -> SafePlace? {
        let loc = app.location.currentLocation ?? CLLocation()
        return journey.corridor.nearbySafePlaces.min {
            $0.distance(from: loc) < $1.distance(from: loc)
        }
    }

    private func nearestSafePlaceCallout(_ place: SafePlace) -> some View {
        let distance = place.distance(from: app.location.currentLocation ?? CLLocation())
        let distanceText = distance < 1000 ? "\(Int(distance)) m" : String(format: "%.1f km", distance / 1000)
        return Button {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
            item.name = place.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        } label: {
            HStack(spacing: 8) {
                Image(systemName: place.type.symbol)
                    .foregroundStyle(place.type.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nearest Safe Place").font(.caption2).foregroundStyle(.secondary)
                    Text("\(place.name) · \(distanceText)").font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: Deviation

    private var deviationCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("You've moved off your planned route.", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                    .foregroundStyle(GuardianTheme.alert)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
                          spacing: 10) {
                    SecondaryActionButton(title: "I'm Safe", systemImage: "checkmark.circle.fill",
                                          tint: GuardianTheme.safe) { app.respondSafe() }
                    SecondaryActionButton(title: "Another Route", systemImage: "arrow.triangle.branch",
                                          tint: GuardianTheme.accent) { app.respondTakingAnotherRoute() }
                    SecondaryActionButton(title: "Get Me Safe", systemImage: "shield.lefthalf.filled",
                                          tint: GuardianTheme.safe) { showGetSafe = true }
                    SecondaryActionButton(title: "SOS", systemImage: "sos",
                                          tint: GuardianTheme.emergency) { app.activateSOS(message: nil) }
                }
            }
        }
    }

    // MARK: Status

    private func statusCard(_ journey: LiveJourney) -> some View {
        GuardianCard {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("To \(journey.destinationName)").font(.headline)
                        Text("ETA \(journey.eta.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    SafetyStatusBadge(state: app.safetyState)
                }
                ProgressView(value: journey.progress).tint(GuardianTheme.accent)
                HStack {
                    metric("Progress", "\(Int(journey.progress * 100))%", "chart.line.uptrend.xyaxis")
                    Divider().frame(height: 34)
                    metric("Confidence", "\(app.confidence.score)", "shield.fill")
                    Divider().frame(height: 34)
                    metric("Route", "\(journey.corridor.routeSafetyScore)", "road.lanes")
                }
                HStack {
                    ConnectivityChip(state: app.connectivity.state, forced: app.connectivity.isForced)
                    Spacer()
                    Text(journey.deviation.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(journey.deviation.mappedState.color)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.caption).foregroundStyle(GuardianTheme.accent)
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Checkpoints

    private func checkpointsCard(_ journey: LiveJourney) -> some View {
        Group {
            if !journey.corridor.checkpoints.isEmpty {
                GuardianCard {
                    VStack(alignment: .leading, spacing: 12) {
                        GuardianSectionHeader(title: "Checkpoints", systemImage: "checkmark.seal.fill")
                        ForEach(journey.corridor.checkpoints) { checkpoint in
                            checkpointRow(checkpoint)
                            if checkpoint.id != journey.corridor.checkpoints.last?.id { Divider() }
                        }
                    }
                }
            } else {
                GuardianCard {
                    Label("This trip is short enough that no en-route checkpoints are needed — Guardian still monitors your position continuously.",
                          systemImage: "checkmark.seal")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func checkpointRow(_ checkpoint: Checkpoint) -> some View {
        HStack(spacing: 10) {
            Image(systemName: checkpoint.reached ? "checkmark.circle.fill" : (checkpoint.safePlaceType?.symbol ?? "circle"))
                .foregroundStyle(checkpoint.reached ? GuardianTheme.safe
                                 : (checkpoint.safePlaceType?.tint ?? .secondary))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(checkpoint.name).font(.subheadline)
                if checkpoint.safePlaceType != nil {
                    HStack(spacing: 5) {
                        Text("Real safe place nearby").font(.caption2).foregroundStyle(.secondary)
                        ProvenanceBadge(provenance: checkpoint.provenance)
                    }
                }
            }
            Spacer()
            if checkpoint.reached {
                Text("Reached").font(.caption).foregroundStyle(GuardianTheme.safe)
            }
        }
    }

    // MARK: Nearby

    private func nearbyCard(_ journey: LiveJourney) -> some View {
        let loc = app.location.currentLocation ?? CLLocation()
        let sorted = journey.corridor.nearbySafePlaces
            .sorted { $0.distance(from: loc) < $1.distance(from: loc) }
            .prefix(10)
        return GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    GuardianSectionHeader(title: "Safe Places Nearby", systemImage: "shield.lefthalf.filled")
                    Spacer()
                    Text("within 5 km").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array(sorted)) { place in
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
                        item.name = place.name
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                    } label: {
                        HStack {
                            SafePlaceRow(place: place, distance: place.distance(from: loc))
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.caption).foregroundStyle(GuardianTheme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    if place.id != sorted.last?.id { Divider() }
                }
                if sorted.isEmpty {
                    Text("Searching for safe places nearby…")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var endButton: some View {
        PrimaryActionButton(title: "End Journey", systemImage: "flag.checkered",
                            color: GuardianTheme.alert) {
            showEndConfirm = true
        }
    }

    private func endJourney(completed: Bool) {
        app.completeJourney(completed: completed, context: context)
    }
}
