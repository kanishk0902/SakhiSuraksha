//
//  SafeRoutingService.swift
//  Guardian
//
//  Client for the local ML-backed safe-routing server (ml/src/main.py, v2 —
//  a self-contained FastAPI app; the old local_server.py wrapper has been
//  retired). This is the app's first feature requiring network connectivity;
//  everything else is on-device/offline-first. The backend combines OSRM
//  routing with a live RandomForest model over a 368k-segment Jaipur street
//  dataset to score and rank route alternatives by safety.
//
//  Honesty notes carried over from the ML pipeline (see ml/README.txt and
//  main.py's own docstring for the full v1→v2 change list):
//   - Crime data is real (NCRB 2001-2005) but applied as a city-wide
//     multiplier, not a per-segment feature — every per-segment crime proxy
//     tested correlated too strongly with police/footfall risk to count as
//     independent signal.
//   - police_risk dominates the model's predictions; lighting/road-type are
//     real but modest contributors.
//   - Tier thresholds (safety_score >75 green, 25-75 yellow, <25 red) are
//     fixed business rules, not statistically derived.
//   - No ground-truth validation exists. Reflected in the UI as a persistent
//     "Beta" badge — never claim more confidence than the model has.
//   - The server returns the disclosed_limitations array itself so the UI
//     stays honest even as the model changes further.
//

import Foundation
import CoreLocation
import SwiftUI

// MARK: - Travel mode

enum TravelMode: String, Codable, CaseIterable, Identifiable {
    case walking, cycling, driving
    var id: String { rawValue }

    var title: String {
        switch self {
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .driving: return "Driving"
        }
    }

    var symbol: String {
        switch self {
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        case .driving: return "car.fill"
        }
    }
}

// MARK: - Safety tier

/// Tier is used for text/labeling only ("Safer"/"Moderate"/"Higher Risk") —
/// the backend doesn't send a display name for it, just the slug. For
/// COLOR, always use the route/location's own `colorHex` (parsed via
/// Color(hex:) below), which is the backend's real computed value — tier
/// classification stays a single source of truth server-side, not
/// reimplemented as a second green/yellow/red → color mapping in Swift.
enum SafetyTier: String, Codable {
    case green, yellow, red

    var title: String {
        switch self {
        case .green:  return "Safer"
        case .yellow: return "Moderate"
        case .red:    return "Higher Risk"
        }
    }
}

extension Color {
    /// Parses a "#RRGGBB" (or "RRGGBB") hex string as sent by the backend's
    /// TIER_COLORS. Falls back to gray only if the string is malformed —
    /// should never happen with a trusted local server, but never crashes.
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        var value: UInt64 = 0
        guard sanitized.count == 6, Scanner(string: sanitized).scanHexInt64(&value) else {
            self = .gray
            return
        }
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

// MARK: - Response models (v2 shape)

/// One ranked route alternative. v2 ranks ALL of OSRM's route alternatives
/// by safety_score descending and returns up to 3 — unlike v1, these are NOT
/// guaranteed to be one-per-tier; all 3 could be the same tier if that's what
/// the real alternatives look like. `rank`/`label` reflect that ordering
/// directly from the server, not a client-side re-derivation.
struct SafeRoute: Identifiable, Codable {
    var id: UUID { UUID() }
    var rank: Int
    var label: String
    var tier: SafetyTier
    var colorHex: String
    /// 0-100, higher = safer — this IS the number to show; there is no
    /// separate inverted/danger-direction score in v2.
    var safetyScore: Double
    var distanceKm: Double
    var durationMin: Double
    var geometry: [[Double]]   // [lon, lat] pairs, GeoJSON order (matches OSRM)

    enum CodingKeys: String, CodingKey {
        case rank, label, tier
        case colorHex = "color"
        case safetyScore = "safety_score"
        case distanceKm = "distance_km"
        case durationMin = "duration_min"
        case geometry
    }

    var coordinates: [CLLocationCoordinate2D] {
        geometry.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
    }

    /// The backend's own real computed color for this route's tier — use
    /// this for rendering, never SafetyTier's case (there is no Swift-side
    /// tier→color mapping; this IS the single source of truth).
    var color: Color { Color(hex: colorHex) }

    /// Real decimal score as sent by the backend (already rounded to 1
    /// decimal server-side, e.g. 87.6) — display this, not an Int rounding
    /// of it, so nothing looks more falsely precise or falsely imprecise
    /// than what the model actually returned.
    var safetyScoreText: String { String(format: "%.1f/100", safetyScore) }

    var distanceText: String {
        distanceKm < 1 ? "\(Int(distanceKm * 1000)) m" : String(format: "%.1f km", distanceKm)
    }

    var durationText: String {
        let minutes = Int(durationMin.rounded())
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}

struct SafeModeResult: Codable {
    /// Ranked safest-first, up to 3. May have fewer than 3 if OSRM didn't
    /// offer that many real alternatives for this mode/trip — never padded.
    var routes: [SafeRoute]?
    var error: String?
}

struct SafeRouteResponse: Codable {
    var modes: [String: SafeModeResult]
    var tierThresholds: TierThresholds?
    var modelVersion: String?
    var disclosedLimitations: [String]?

    enum CodingKeys: String, CodingKey {
        case modes
        case tierThresholds = "tier_thresholds"
        case modelVersion = "model_version"
        case disclosedLimitations = "disclosed_limitations"
    }

    /// Fixed business thresholds on the 0-100 safety_score scale (v2) —
    /// NOT derived from the dataset's score distribution the way v1's
    /// percentile-based green_max/yellow_max were.
    struct TierThresholds: Codable {
        var greenMin: Double
        var yellowMin: Double
        enum CodingKeys: String, CodingKey {
            case greenMin = "green_min"
            case yellowMin = "yellow_min"
        }
    }
}

// MARK: - Location safety (point score, not a route)

/// Safety score for the user's current position, not a route — backs the
/// Safety Score screen's ML section. Distinct data from route scoring, but
/// the exact same model/coverage-check pipeline server-side.
/// One factor behind a location's score, as reported by the backend.
///
/// `risk` is the model's own 0-1 input for this factor (1 = worst) and is nil
/// for anything that isn't a per-segment model input; `detail` is the real
/// measured quantity behind it ("Nearest station ~3.1 km away"), so the app
/// shows what was actually measured rather than a bare adjective.
struct SafetyFactor: Codable, Identifiable {
    var key: String
    var label: String
    var risk: Double?
    var detail: String
    /// True for factors applied identically across the whole city (the NCRB
    /// crime multiplier), which therefore explain nothing about why THIS
    /// street differs from another. Shown, but marked as such.
    var citywide: Bool?

    var id: String { key }

    /// 0-100 where higher is better, for display. Nil when there's no
    /// per-segment risk to convert (e.g. the citywide crime factor).
    var contributionScore: Int? {
        risk.map { Int(((1 - $0) * 100).rounded()) }
    }
}

struct LocationSafety: Codable {
    var lat: Double
    var lon: Double
    var safetyScore: Double
    var tier: SafetyTier
    var colorHex: String
    var matchedSegmentDistanceMeters: Double
    var factors: [SafetyFactor]?
    var modelVersion: String?
    var disclosedLimitations: [String]?

    enum CodingKeys: String, CodingKey {
        case lat, lon, tier, factors
        case safetyScore = "safety_score"
        case colorHex = "color"
        case matchedSegmentDistanceMeters = "matched_segment_distance_m"
        case modelVersion = "model_version"
        case disclosedLimitations = "disclosed_limitations"
    }

    var safetyScoreRounded: Int { Int(safetyScore.rounded()) }

    /// The backend's own real computed color — see SafeRoute.color's doc
    /// comment; same principle, single source of truth stays server-side.
    var color: Color { Color(hex: colorHex) }
}

// MARK: - Errors

enum SafeRoutingError: LocalizedError {
    case serverUnreachable
    case invalidResponse
    case serverError(String)
    case outOfCoverage(String)

    var errorDescription: String? {
        switch self {
        case .serverUnreachable:
            return "Safety routing is unavailable right now. Make sure the local routing server is running."
        case .invalidResponse:
            return "Safety routing returned an unexpected response."
        case .serverError:
            return "Safety routing couldn't calculate a route right now. Please try again."
        case .outOfCoverage(let message):
            return message
        }
    }
}

// MARK: - Service

@Observable
final class SafeRoutingService {

    private(set) var isLoading = false
    private(set) var lastError: SafeRoutingError?
    private(set) var lastResponse: SafeRouteResponse?

    private(set) var isLoadingLocationSafety = false
    private(set) var locationSafetyError: SafeRoutingError?
    private(set) var locationSafety: LocationSafety?

    /// Addresses to try for the local dev ML server, in order. The first one
    /// that answers /health is remembered in `baseURL` for the rest of the
    /// session (see resolveBaseURL).
    ///
    /// WHY A LIST: this is a dev server on a Mac, reached over whatever
    /// network both devices happen to be on, and the Mac's address changes
    /// every time that network changes — hardcoding one value meant editing
    /// this file and rebuilding after each switch. "localhost" covers the
    /// Simulator (where it means the Mac itself); the 172.20.10.x entry is
    /// the standard iPhone Personal Hotspot range.
    ///
    /// NOTE ON PUBLIC/CAMPUS WI-FI: many such networks enable client (AP)
    /// isolation, which blocks phone→Mac connections outright. The giveaway
    /// is that even Safari on the phone can't load http://<mac-ip>:8000/health
    /// while the Mac's own server, firewall and ATS all check out. A Personal
    /// Hotspot avoids this entirely, which is why its range is listed here.
    ///
    /// Add the Mac's current `ipconfig getifaddr en0` value here if it isn't
    /// covered; unreachable entries just fail fast and fall through.
    static let candidateHosts = [
        "http://localhost:8000",
        "http://172.20.10.3:8000",
        "http://10.58.183.99:8000",
    ]

    /// The address confirmed to answer, once one has. Starts at the first
    /// candidate so requests made before discovery finishes still have a
    /// sensible target.
    var baseURL = URL(string: SafeRoutingService.candidateHosts[0])!
    private var hasResolvedBaseURL = false

    /// Finds a reachable server address, cheaply (2s timeout per candidate)
    /// and only once per session. Called before each request; a no-op after
    /// the first success.
    private func resolveBaseURL() async {
        guard !hasResolvedBaseURL else { return }
        for host in Self.candidateHosts {
            guard let url = URL(string: host) else { continue }
            var request = URLRequest(url: url.appendingPathComponent("health"))
            request.timeoutInterval = 2
            if let (_, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                baseURL = url
                hasResolvedBaseURL = true
                return
            }
        }
    }

    func fetchSafeRoutes(from start: CLLocationCoordinate2D,
                         to end: CLLocationCoordinate2D,
                         modes: [TravelMode] = TravelMode.allCases) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        await resolveBaseURL()

        var request = URLRequest(url: baseURL.appendingPathComponent("safe-routes"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let body: [String: Any] = [
            "start_lat": start.latitude,
            "start_lon": start.longitude,
            "end_lat": end.latitude,
            "end_lon": end.longitude,
            "modes": modes.map(\.rawValue),
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = .invalidResponse
                return
            }
            guard http.statusCode == 200 else {
                // 422 is the server's honest "outside Jaipur coverage" error
                // (see main.py's check_coverage) — surfaced distinctly from a
                // generic failure so the user understands why, rather than
                // a vague "try again" that implies retrying would help.
                if http.statusCode == 422,
                   let decoded = try? JSONDecoder().decode([String: String].self, from: data),
                   let detail = decoded["detail"] {
                    lastError = .outOfCoverage(detail)
                } else if let decoded = try? JSONDecoder().decode([String: String].self, from: data),
                          decoded["error"] != nil || decoded["detail"] != nil {
                    lastError = .serverError(decoded["error"] ?? decoded["detail"] ?? "")
                } else {
                    lastError = .invalidResponse
                }
                return
            }
            let decoded = try JSONDecoder().decode(SafeRouteResponse.self, from: data)
            lastResponse = decoded
        } catch is URLError {
            lastError = .serverUnreachable
        } catch {
            lastError = .invalidResponse
        }
    }

    func reset() {
        lastResponse = nil
        lastError = nil
    }

    /// Fetches the ML safety score for a single point (the user's current
    /// location), not a route. Used by SafetyScoreView to show a distinct,
    /// clearly-labeled ML section alongside the on-device SafetyEngine score
    /// — never merged into one number, since they measure different things.
    func fetchLocationSafety(at coordinate: CLLocationCoordinate2D) async {
        isLoadingLocationSafety = true
        locationSafetyError = nil
        defer { isLoadingLocationSafety = false }
        await resolveBaseURL()

        var request = URLRequest(url: baseURL.appendingPathComponent("location-safety"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        let body: [String: Any] = ["lat": coordinate.latitude, "lon": coordinate.longitude]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                locationSafetyError = .invalidResponse
                return
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 422,
                   let decoded = try? JSONDecoder().decode([String: String].self, from: data),
                   let detail = decoded["detail"] {
                    locationSafetyError = .outOfCoverage(detail)
                } else {
                    locationSafetyError = .serverError("")
                }
                return
            }
            locationSafety = try JSONDecoder().decode(LocationSafety.self, from: data)
        } catch is URLError {
            locationSafetyError = .serverUnreachable
        } catch {
            locationSafetyError = .invalidResponse
        }
    }

    /// Scores a route the app already has (e.g. from MapKit) with the real
    /// model, via POST /score-route. Throws rather than returning a fallback
    /// number: a caller must decide how to show "no score", never silently
    /// display a guess as if it were a measurement.
    func scoreExistingRoute(_ route: [CLLocationCoordinate2D],
                            mode: String = "walking") async throws -> Int {
        guard route.count >= 2 else { throw SafeRoutingError.invalidResponse }
        await resolveBaseURL()

        var request = URLRequest(url: baseURL.appendingPathComponent("score-route"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        // [lon, lat] to match the server's GeoJSON-style ordering.
        let coords = route.map { [$0.longitude, $0.latitude] }
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["coordinates": coords, "mode": mode])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SafeRoutingError.invalidResponse
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 422,
                   let decoded = try? JSONDecoder().decode([String: String].self, from: data),
                   let detail = decoded["detail"] {
                    throw SafeRoutingError.outOfCoverage(detail)
                }
                throw SafeRoutingError.serverError("")
            }
            struct RouteScore: Decodable {
                let safetyScore: Double
                enum CodingKeys: String, CodingKey { case safetyScore = "safety_score" }
            }
            let decoded = try JSONDecoder().decode(RouteScore.self, from: data)
            return Int(decoded.safetyScore.rounded())
        } catch let error as SafeRoutingError {
            throw error
        } catch is URLError {
            throw SafeRoutingError.serverUnreachable
        } catch {
            throw SafeRoutingError.invalidResponse
        }
    }
}

/// RouteSafetyProvider backed by the real ML model (POST /score-route).
///
/// Replaces LocalRouteSafetyProvider for journey/navigation route scores.
/// That one started from a hardcoded 78 and added invented point values for
/// CCTV coverage, incident counts, safe-place proximity and route tortuosity —
/// a number with the look of a measurement and none of the substance. This
/// asks the same model the Safe Route screen uses, so one route has one score
/// throughout the app.
struct MLRouteSafetyProvider: RouteSafetyProvider {
    let routing: SafeRoutingService
    var mode: String = "walking"

    func safetyScore(for route: [CLLocationCoordinate2D]) async throws -> Int {
        try await routing.scoreExistingRoute(route, mode: mode)
    }
}
