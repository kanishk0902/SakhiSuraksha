//
//  SafeRoutingService.swift
//  Guardian
//
//  Client for the local ML-backed safe-routing server (ml/src/local_server.py
//  — a FastAPI wrapper around ml/src/main.py, unmodified). This is the app's
//  first feature requiring network connectivity; everything else is
//  on-device/offline-first. The backend combines OSRM routing with a
//  pre-scored Jaipur street-segment dataset (368k segments) to classify
//  routes into green/yellow/red safety tiers.
//
//  Honesty notes carried over from the ML pipeline (see ml/README and
//  main.py docstring):
//   - 2 of 5 intended safety signals (lighting, crime) are constant
//     placeholders with zero real signal — the score is really driven by
//     road type, police proximity, and footfall density only.
//   - Tier thresholds are data-driven (33rd/66th percentile of real scores)
//     but were only spot-checked against ~10 routes, not statistically
//     validated. This is reflected in the UI as a persistent "Beta" badge —
//     never claim more confidence than the model has.
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

enum SafetyTier: String, Codable {
    case green, yellow, red

    var title: String {
        switch self {
        case .green:  return "Safer"
        case .yellow: return "Moderate"
        case .red:    return "Higher Risk"
        }
    }

    var color: Color {
        switch self {
        case .green:  return GuardianTheme.safe
        case .yellow: return GuardianTheme.caution
        case .red:    return GuardianTheme.emergency
        }
    }
}

// MARK: - Response models

struct SafeRoute: Identifiable, Codable {
    var id: UUID { UUID() }
    var routeIndex: Int
    var geometry: [[Double]]   // [lon, lat] pairs, GeoJSON order (matches OSRM)
    var distanceMeters: Double
    var durationSeconds: Double
    var worstScore: Double
    var adjustedScore: Double
    var tier: SafetyTier

    enum CodingKeys: String, CodingKey {
        case routeIndex = "route_index"
        case geometry
        case distanceMeters = "distance_m"
        case durationSeconds = "duration_s"
        case worstScore = "worst_score"
        case adjustedScore = "adjusted_score"
        case tier
    }

    var coordinates: [CLLocationCoordinate2D] {
        geometry.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
    }

    /// 0-100, higher = safer. Presentation-only inversion of adjusted_score
    /// for readability — the underlying tier classification always uses the
    /// backend's own tercile cutoffs, not this rounded number.
    var safetyScore100: Int {
        Int(((1 - adjustedScore).clamped(to: 0...1)) * 100)
    }

    var distanceText: String {
        distanceMeters < 1000 ? "\(Int(distanceMeters)) m" : String(format: "%.1f km", distanceMeters / 1000)
    }

    var durationText: String {
        let minutes = Int(durationSeconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}

struct SafeModeResult: Codable {
    var bestPerTier: [String: SafeRoute]?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case bestPerTier = "best_per_tier"
        case error
    }

    var routesByTier: [SafetyTier: SafeRoute] {
        guard let bestPerTier else { return [:] }
        var out: [SafetyTier: SafeRoute] = [:]
        for (key, route) in bestPerTier {
            if let tier = SafetyTier(rawValue: key) { out[tier] = route }
        }
        return out
    }
}

struct SafeRouteResponse: Codable {
    var modes: [String: SafeModeResult]
    var tierThresholds: TierThresholds?

    enum CodingKeys: String, CodingKey {
        case modes
        case tierThresholds = "tier_thresholds"
    }

    struct TierThresholds: Codable {
        var greenMax: Double
        var yellowMax: Double
        enum CodingKeys: String, CodingKey {
            case greenMax = "green_max"
            case yellowMax = "yellow_max"
        }
    }
}

// MARK: - Errors

enum SafeRoutingError: LocalizedError {
    case serverUnreachable
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .serverUnreachable:
            return "Safety routing is unavailable right now. Make sure the local routing server is running."
        case .invalidResponse:
            return "Safety routing returned an unexpected response."
        case .serverError(let message):
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

    /// Base URL of the local dev server. Simulator reaches the Mac via
    /// localhost; a physical device on the same Wi-Fi needs the Mac's LAN IP
    /// here instead (see ml/README.txt). Not persisted/configurable in the
    /// UI yet — this is a dev/demo setup, see the service's file header.
    var baseURL = URL(string: "http://localhost:8000")!

    func fetchSafeRoutes(from start: CLLocationCoordinate2D,
                         to end: CLLocationCoordinate2D,
                         modes: [TravelMode] = TravelMode.allCases) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

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
                if let decoded = try? JSONDecoder().decode([String: String].self, from: data),
                   let message = decoded["error"] {
                    lastError = .serverError(message)
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
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
