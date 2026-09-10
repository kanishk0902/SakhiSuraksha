//
//  SafeRouteView.swift
//  Guardian
//
//  ML-backed Safe Route planner: search a destination, then see walking/
//  cycling/driving options ranked by a route-safety model trained on ~368k
//  scored Jaipur street segments (see ml/README.txt and SafeRoutingService's
//  header for the full honesty notes). This is distinct from SafetyTabView's
//  on-device "Fastest vs Safer" comparison, which uses sparse local
//  incident/CCTV data — this screen uses the richer offline dataset via a
//  local server, and is the app's first feature that requires network
//  connectivity.
//
//  v2 note: routes are ranked safest-first (up to 3, however many OSRM
//  actually offers), not one-per-tier like the old model — all displayed
//  routes could be the same tier if that's what the real alternatives are.
//

import SwiftUI
import MapKit
import CoreLocation

struct SafeRouteView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var routing = SafeRoutingService()
    @State private var search = AddressSearchService()
    @State private var destinationName: String = ""
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var showSearchResults = false
    @State private var selectedMode: TravelMode = .walking
    @State private var didAutoSelectMode = false
    @State private var selectedRouteRank: Int = 1
    @State private var showLimitations = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if destinationCoordinate == nil {
                    searchState
                } else {
                    resultsState
                }
            }
            .navigationTitle("Safe Route")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if destinationCoordinate != nil {
                    ToolbarItem(placement: .guardianTrailing) {
                        Button("New Search") {
                            destinationCoordinate = nil
                            routing.reset()
                        }
                    }
                }
            }
        }
    }

    // MARK: Search state

    private var searchState: some View {
        ScrollView {
            VStack(spacing: GuardianTheme.cardSpacing) {
                GuardianCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("ML Safe Route", systemImage: "shield.checkerboard")
                            .font(.headline)
                        Text("Compares walking, cycling and driving routes to your destination and ranks them safest-first using a model trained on Jaipur street data.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        BetaBadge()
                    }
                }

                GuardianCard {
                    VStack(alignment: .leading, spacing: 12) {
                        GuardianSectionHeader(title: "Where are you going?", systemImage: "magnifyingglass")
                        HStack {
                            Image(systemName: "flag.checkered.circle.fill")
                                .foregroundStyle(GuardianTheme.accent)
                            TextField("Search destination…", text: $search.query)
                                .autocorrectionDisabled()
                            if !search.query.isEmpty {
                                Button {
                                    search.query = ""
                                    showSearchResults = false
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                            }
                        }

                        if showSearchResults && !search.results.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(search.results.prefix(6), id: \.title) { result in
                                    Button {
                                        Task { await selectResult(result) }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                            if !result.subtitle.isEmpty {
                                                Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 10)
                                    }
                                    if result.title != search.results.prefix(6).last?.title { Divider() }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .onChange(of: search.query) { _, new in showSearchResults = !new.isEmpty }
    }

    private func selectResult(_ result: MKLocalSearchCompletion) async {
        guard let coord = await search.resolve(result) else { return }
        destinationCoordinate = coord
        destinationName = result.title
        search.query = result.title
        showSearchResults = false
        preselectDetectedMode()
        await fetchRoutes()
    }

    private func preselectDetectedMode() {
        guard !didAutoSelectMode else { return }
        didAutoSelectMode = true
        selectedMode = app.location.detectedMode
    }

    // MARK: Results state

    private var resultsState: some View {
        VStack(spacing: 0) {
            modePicker

            if routing.isLoading {
                Spacer()
                ProgressView("Finding safe routes…")
                Spacer()
            } else if let error = routing.lastError {
                unavailableState(error)
            } else if let response = routing.lastResponse {
                resultsMap(response)
            } else {
                Spacer()
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(TravelMode.allCases) { mode in
                Button {
                    selectedMode = mode
                    selectedRouteRank = 1
                    Haptics.tap()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.symbol)
                        Text(mode.title).font(.caption2.weight(.semibold))
                        if mode == app.location.detectedMode {
                            Text("Detected").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedMode == mode ? GuardianTheme.accent.opacity(0.18) : Color.clear)
                    .foregroundStyle(selectedMode == mode ? GuardianTheme.accent : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func resultsMap(_ response: SafeRouteResponse) -> some View {
        // The mode picker focuses the map on one mode's routes at a time
        // (drawing all three modes' routes together would be visual noise),
        // but the summary below always lists all requested modes at once.
        let modeRoutes = response.modes[selectedMode.rawValue]?.routes ?? []

        return VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Map {
                    UserAnnotation()
                    if let destinationCoordinate {
                        Marker("Destination", systemImage: "flag.checkered", coordinate: destinationCoordinate)
                            .tint(GuardianTheme.accent)
                    }
                    // Draw all ranked routes, dimming the non-selected ones so
                    // the chosen route is visually dominant while the
                    // alternatives (for context) are still visible.
                    ForEach(modeRoutes) { route in
                        MapPolyline(coordinates: route.coordinates)
                            .stroke(route.rank == selectedRouteRank ? route.color : route.color.opacity(0.35),
                                    style: StrokeStyle(lineWidth: route.rank == selectedRouteRank ? 6 : 4, lineCap: .round))
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                if let modeResult = response.modes[selectedMode.rawValue], modeResult.error != nil {
                    modeErrorCard(modeResult.error ?? "This mode is unavailable.")
                }
            }

            if !modeRoutes.isEmpty {
                scoreSourceHeader(response)
                rankedRoutesList(modeRoutes)
            }
            allModesSummary(response)
        }
        .sheet(isPresented: $showLimitations) {
            limitationsSheet(response.disclosedLimitations ?? [])
        }
    }

    /// Genuinely visible disclosure of the real disclosed_limitations array
    /// from the API — not a buried fine-print footer. Placed directly next
    /// to the scores it qualifies, and it's the exact list the backend sent,
    /// never a client-side paraphrase.
    private func scoreSourceHeader(_ response: SafeRouteResponse) -> some View {
        HStack(spacing: 6) {
            if let version = response.modelVersion {
                Text("Model \(version)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showLimitations = true
            } label: {
                Label("Limitations", systemImage: "info.circle")
                    .font(.caption2.weight(.semibold))
            }
            .disabled((response.disclosedLimitations ?? []).isEmpty)
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }

    private func limitationsSheet(_ limitations: [String]) -> some View {
        NavigationStack {
            List(limitations, id: \.self) { item in
                Text(item).font(.subheadline)
            }
            .navigationTitle("Model Limitations")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showLimitations = false }
                }
            }
        }
    }

    /// The current mode's ranked routes (safest-first, up to 3) — tapping one
    /// selects it on the map above. All 3 can be the same tier; that's v2's
    /// real "top 3 safest overall" ranking, not one-per-tier like v1.
    private func rankedRoutesList(_ routes: [SafeRoute]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(routes) { route in
                    Button {
                        selectedRouteRank = route.rank
                        Haptics.tap()
                    } label: {
                        GuardianCard(padding: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Circle().fill(route.color).frame(width: 8, height: 8)
                                    Text(route.label).font(.caption.weight(.semibold))
                                    if route.rank == selectedRouteRank {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(GuardianTheme.accent)
                                    }
                                }
                                Text("\(route.durationText) · \(route.distanceText)")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text("Safety \(route.safetyScoreText)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(route.color)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: GuardianTheme.cornerRadius)
                                .stroke(route.rank == selectedRouteRank ? GuardianTheme.accent : .clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: 150)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    /// All three modes' safest route, shown together — tapping a mode's row
    /// also switches the map above to that mode's ranked routes.
    private func allModesSummary(_ response: SafeRouteResponse) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(TravelMode.allCases) { mode in
                    modeSummaryCard(mode: mode, result: response.modes[mode.rawValue])
                }
            }
            .padding()
        }
        .background(.thinMaterial)
    }

    private func modeSummaryCard(mode: TravelMode, result: SafeModeResult?) -> some View {
        let safest = result?.routes?.first
        return Button {
            selectedMode = mode
            selectedRouteRank = 1
            Haptics.tap()
        } label: {
            GuardianCard(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: mode.symbol)
                        Text(mode.title).font(.subheadline.weight(.semibold))
                        if selectedMode == mode {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(GuardianTheme.accent)
                        }
                    }
                    if let error = result?.error {
                        Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    } else if let safest {
                        HStack(spacing: 5) {
                            Circle().fill(safest.color).frame(width: 8, height: 8)
                            Text(safest.tier.title).font(.caption2)
                        }
                        Text("\(safest.durationText) · \(safest.distanceText)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Score \(safest.safetyScoreText)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(safest.color)
                    } else {
                        ProgressView().scaleEffect(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(
                RoundedRectangle(cornerRadius: GuardianTheme.cornerRadius)
                    .stroke(selectedMode == mode ? GuardianTheme.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .frame(width: 170)
    }

    private func modeErrorCard(_ message: String) -> some View {
        GuardianCard {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(GuardianTheme.caution)
        }
        .padding()
    }

    private func unavailableState(_ error: SafeRoutingError) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Safety Routing Unavailable")
                .font(.headline)
            Text(error.errorDescription ?? "Something went wrong.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await fetchRoutes() }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private func fetchRoutes() async {
        guard let destinationCoordinate else { return }
        let origin = app.location.currentLocation?.coordinate ?? LocationService.fallbackCoordinate
        await routing.fetchSafeRoutes(from: origin, to: destinationCoordinate)
    }
}

// MARK: - Beta badge

/// Persistent, honest indicator that this score is beta. Deliberately
/// generic (shown before any request completes, so no real per-response
/// disclosed_limitations data exists yet) — the specific, real limitation
/// list is shown after a request via the "Limitations" button, sourced
/// directly from the API response's disclosed_limitations field, not
/// paraphrased here.
struct BetaBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flask.fill")
            Text("Beta Safety Score — see \"Limitations\" on results for what this model does and doesn't account for.")
        }
        .font(.caption2)
        .foregroundStyle(GuardianTheme.caution)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(GuardianTheme.caution.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
