//
//  SafetyDataService.swift
//  Guardian
//
//  Safe places are discovered via real MKLocalSearch and cached locally for
//  offline use. Incidents, CCTV, and zone data return empty — those require
//  external data providers that are not yet integrated. Provenance is always
//  honest: .real for live MapKit results, .cached for locally-stored results.
//

import Foundation
import CoreLocation
import MapKit
import Observation

@Observable
final class SafetyDataService {

    private(set) var safePlaces: [SafePlace] = []
    private(set) var incidents: [Incident] = []          // empty — no real data source yet
    private(set) var cctv: [CCTVEvent] = []               // empty — no real data source yet
    private(set) var zones: [SafetyZone] = []             // empty — no real data source yet
    private(set) var isSearching = false
    private(set) var lastSearchCoordinate: CLLocationCoordinate2D?
    private(set) var dataProviderStatus = "Safe places: live MapKit search · Incidents/CCTV: no data source connected"

    private let cacheKey = "guardian.safePlacesCache.v2"
    private let searchRadiusMeters: Double = 5000
    private let movementThreshold: Double = 400  // only refresh after moving 400 m

    // MARK: Refresh trigger

    func refresh(around center: CLLocationCoordinate2D, force: Bool = false) {
        if !force, let last = lastSearchCoordinate {
            guard last.location.distance(from: center.location) >= movementThreshold else { return }
        }
        Task { await searchPlaces(near: center) }
    }

    /// Awaitable version of `refresh(force:)` — used where a caller needs
    /// `safePlaces` to actually be populated before proceeding (e.g.
    /// building a journey corridor that snaps checkpoints to real nearby
    /// places), rather than the fire-and-forget Task the plain `refresh`
    /// kicks off.
    func refreshAndWait(around center: CLLocationCoordinate2D) async {
        await searchPlaces(near: center)
    }

    // MARK: Real MKLocalSearch

    private func searchPlaces(near center: CLLocationCoordinate2D) async {
        isSearching = true
        defer { isSearching = false }
        lastSearchCoordinate = center

        // Each query maps to a SafePlaceType so results are categorised correctly.
        let queries: [(String, SafePlaceType)] = [
            ("police station",  .police),
            ("hospital",        .hospital),
            ("fire station",    .publicBuilding),
            ("train station",   .transit),
            ("metro station",   .transit),
            ("pharmacy",        .business),
            ("public library",  .publicBuilding),
        ]

        let region = MKCoordinateRegion(center: center,
                                        latitudinalMeters: searchRadiusMeters,
                                        longitudinalMeters: searchRadiusMeters)
        var found: [SafePlace] = []

        for (query, type) in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = region
            request.resultTypes = .pointOfInterest
            do {
                let response = try await MKLocalSearch(request: request).start()
                let places = response.mapItems.prefix(8).compactMap { item -> SafePlace? in
                    guard let name = item.name else { return nil }
                    return SafePlace(name: name,
                                     type: type,
                                     coordinate: item.placemark.coordinate,
                                     safetyScore: type.defaultSafetyScore,
                                     isVerified: false,
                                     provenance: .real,
                                     openNow: true)
                }
                found.append(contentsOf: places)
            } catch {
                // Network unavailable or no results for this query — continue.
            }
        }

        if !found.isEmpty {
            safePlaces = found
            cachePlaces(found)
            dataProviderStatus = "Safe places: \(found.count) found near you (MapKit)"
        } else {
            // Offline or no results — fall back to cache.
            let cached = loadCachedPlaces()
            safePlaces = cached.map { p in
                SafePlace(id: p.id, name: p.name, type: p.type,
                          coordinate: p.coordinate, safetyScore: p.safetyScore,
                          isVerified: p.isVerified, provenance: .cached, openNow: p.openNow)
            }
            dataProviderStatus = safePlaces.isEmpty
                ? "Safe places: no data — check internet connection"
                : "Safe places: \(safePlaces.count) from cache (offline)"
        }
    }

    // MARK: UserDefaults cache

    private func cachePlaces(_ places: [SafePlace]) {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func loadCachedPlaces() -> [SafePlace] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let places = try? JSONDecoder().decode([SafePlace].self, from: data) else { return [] }
        return places
    }

    // MARK: "Get Me Somewhere Safe" ranking

    func rankedDestinations(from location: CLLocation, safetyConfidence: Int) -> [SafeDestination] {
        safePlaces
            .map { place in
                let d = place.distance(from: location)
                return SafeDestination(place: place, distance: d,
                                       rankedScore: Self.rankingScore(place: place, distance: d,
                                                                      confidence: safetyConfidence))
            }
            .sorted { $0.rankedScore > $1.rankedScore }
    }

    private static func rankingScore(place: SafePlace, distance: CLLocationDistance,
                                     confidence: Int) -> Int {
        let distScore = max(0.0, 100.0 - (distance / 20.0))
        let typePriority: Double
        switch place.type {
        case .police:         typePriority = 100
        case .hospital:       typePriority = 95
        case .transit:        typePriority = 80
        case .publicBuilding: typePriority = 70
        case .safeSpot:       typePriority = 78
        case .business:       typePriority = 65
        }
        let openBonus: Double  = place.openNow ? 8 : -12
        let urgency = Double(max(0, 60 - confidence)) / 60.0
        let combined = distScore * 0.35
                     + Double(place.safetyScore) * 0.30
                     + typePriority * (0.25 + 0.15 * urgency)
                     + openBonus
        return min(100, max(0, Int(combined)))
    }
}

// MARK: - Provider protocols (future external data sources)

/// Future external incident/crime/alert data provider.
protocol SafetyIncidentProvider {
    func incidents(near coordinate: CLLocationCoordinate2D,
                   radiusMeters: Double) async throws -> [Incident]
}

/// Future CCTV/anomaly data provider (e.g. CV backend).
protocol CCTVDataProvider {
    func coverage(near coordinate: CLLocationCoordinate2D,
                  radiusMeters: Double) async throws -> [CCTVEvent]
}

/// Future route safety provider (lighting, crowd, crime risk per route segment).
protocol RouteSafetyProvider {
    func safetyScore(for route: [CLLocationCoordinate2D]) async throws -> Int
}

/// NOTE: LocalRouteSafetyProvider was removed here. It scored routes from a
/// hardcoded base (78) plus invented point values for CCTV coverage, incident
/// counts, safe-place proximity and route tortuosity, clamped to 30-100 — so
/// it always returned a confident-looking number regardless of whether any
/// real data backed it. Route scoring now goes through MLRouteSafetyProvider
/// (see SafeRoutingService), which asks the actual model.

// MARK: - SafePlaceType scoring defaults

extension SafePlaceType {
    var defaultSafetyScore: Int {
        switch self {
        case .police:         return 90
        case .hospital:       return 88
        case .publicBuilding: return 75
        case .safeSpot:       return 80
        case .transit:        return 72
        case .business:       return 68
        }
    }
}
