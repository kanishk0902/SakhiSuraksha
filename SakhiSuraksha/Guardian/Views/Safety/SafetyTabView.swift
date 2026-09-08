//
//  SafetyTabView.swift
//  Guardian
//
//  The map-based Safety screen with layered filters, plus quick access to the
//  safety score breakdown and compass.
//

import SwiftUI
import CoreLocation

struct SafetyTabView: View {
    @Environment(AppModel.self) private var app
    @State private var filter: Filter = .all
    @State private var routeScores: [Int: Int] = [:]  // index into candidateRoutes -> score

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case safe = "Safe Places"
        case incidents = "Incidents"
        case cctv = "CCTV"
        case mesh = "Mesh"
        case emergency = "Emergency"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if app.journey.isActive { routeComparisonCard }
                mapArea
            }
            .navigationTitle("Safety Map")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .guardianTrailing) {
                    NavigationLink { CompassView() } label: {
                        Image(systemName: "location.north.line.fill")
                    }
                    .accessibilityLabel("Open compass")
                }
            }
            .task(id: app.journey.active?.id) { await scoreCandidateRoutes() }
        }
    }

    // MARK: Safe Route — Fastest vs Safer

    /// The active journey's primary route plus its cached alternates, each
    /// paired with an estimated walking time (1.35 m/s, matching
    /// RoutingService's synthetic-route pacing) and distance.
    private var candidateRoutes: [(name: String, coords: [CLLocationCoordinate2D])] {
        guard let journey = app.journey.active else { return [] }
        var list: [(String, [CLLocationCoordinate2D])] = [("Fastest", journey.corridor.routeCoordinates)]
        if let alt = journey.corridor.alternateRoutes.first {
            list.append(("Safer", alt))
        }
        return list
    }

    private func scoreCandidateRoutes() async {
        let provider = LocalRouteSafetyProvider(data: app.safetyData)
        var scores: [Int: Int] = [:]
        for (index, candidate) in candidateRoutes.enumerated() {
            scores[index] = (try? await provider.safetyScore(for: candidate.coords)) ?? 50
        }
        routeScores = scores
    }

    private var routeComparisonCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    GuardianSectionHeader(title: "Safe Route", systemImage: "shield.checkerboard")
                    Spacer()
                    ProvenanceBadge(provenance: .real)
                }
                ForEach(Array(candidateRoutes.enumerated()), id: \.offset) { index, candidate in
                    routeRow(index: index, candidate: candidate)
                    if index != candidateRoutes.count - 1 { Divider() }
                }
                Text("Score reflects reported incidents and CCTV coverage near this route. No incidents are reported near you yet, so routes score similarly until real reports exist.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func routeRow(index: Int, candidate: (name: String, coords: [CLLocationCoordinate2D])) -> some View {
        let meters = routeLength(candidate.coords)
        let minutes = max(1, Int((meters / 1.35) / 60))
        let score = routeScores[index]
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name).font(.subheadline.weight(.semibold))
                Text("\(minutes) min · \(String(format: "%.1f km", meters / 1000))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let score {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(score)").font(.title3.weight(.bold))
                        .foregroundStyle(SafetyState.passive.color.opacity(Double(score) / 100 + 0.3))
                    Text("Safety Score").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                ProgressView().scaleEffect(0.8)
            }
        }
    }

    private func routeLength(_ coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<coords.count {
            total += coords[i].location.distance(from: coords[i-1].location)
        }
        return total
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { filter = item }
                        Haptics.tap()
                    } label: {
                        Text(item.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(filter == item ? GuardianTheme.accent : Color.secondary.opacity(0.15))
                            .foregroundStyle(filter == item ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private var mapArea: some View {
        ZStack(alignment: .bottom) {
            GuardianMap(routes: routes,
                        saferRoute: saferRoute,
                        safePlaces: filteredPlaces,
                        incidents: filteredIncidents,
                        cctv: filteredCCTV,
                        zones: filter == .all ? app.safetyData.zones : [],
                        meshNodes: filteredMeshCoords,
                        destination: app.journey.active?.destination)
                .ignoresSafeArea(edges: .bottom)
            legend
        }
    }

    private var legend: some View {
        GuardianCard(padding: 12) {
            HStack {
                Label("\(app.confidence.score)", systemImage: "shield.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(app.safetyState.color)
                Divider().frame(height: 20)
                Text(app.safetyState.title).font(.caption.weight(.semibold))
                Spacer()
                NavigationLink { SafetyScoreView() } label: {
                    Text("Why?").font(.caption.weight(.semibold))
                }
            }
        }
        .padding()
    }

    // MARK: Filtered layers

    private var filteredPlaces: [SafePlace] {
        switch filter {
        case .all, .safe: return app.safetyData.safePlaces
        case .emergency:  return app.safetyData.safePlaces.filter { $0.type == .police || $0.type == .hospital }
        default:          return []
        }
    }

    private var filteredIncidents: [Incident] {
        (filter == .all || filter == .incidents || filter == .emergency) ? app.safetyData.incidents : []
    }

    private var filteredCCTV: [CCTVEvent] {
        (filter == .all || filter == .cctv) ? app.safetyData.cctv : []
    }

    // Real MPC peers don't broadcast their GPS coordinates.
    // Mesh filter shows no pins until peer location sharing is implemented.
    private var filteredMeshCoords: [CLLocationCoordinate2D] { [] }

    private var routes: [[CLLocationCoordinate2D]] {
        guard let journey = app.journey.active else { return [] }
        return [journey.corridor.routeCoordinates]
    }

    private var saferRoute: [CLLocationCoordinate2D]? {
        app.journey.active?.corridor.alternateRoutes.first
    }
}
