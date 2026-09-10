//
//  RoutingService.swift
//  Guardian
//
//  Wraps MapKit directions. When online it requests a real walking route; when
//  that is unavailable (offline / simulator) it synthesizes a plausible route
//  so the Safety Corridor can still be cached and displayed.
//

import Foundation
import MapKit

struct RouteStep: Identifiable {
    let id = UUID()
    var instructions: String
    var distance: CLLocationDistance
    /// Where this step begins along the route — used to detect which step
    /// the user is currently on as they move.
    var startCoordinate: CLLocationCoordinate2D
}

struct RouteResult {
    var coordinates: [CLLocationCoordinate2D]
    var travelTime: TimeInterval
    var distance: CLLocationDistance
    var provenance: DataProvenance
    var steps: [RouteStep] = []
}

@Observable
final class RoutingService {

    /// Compute a primary route. Falls back to a synthetic path if MapKit fails.
    func route(from origin: CLLocationCoordinate2D,
               to destination: CLLocationCoordinate2D) async -> RouteResult {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        request.requestsAlternateRoutes = true

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            if let best = response.routes.first {
                let steps = best.steps
                    .filter { !$0.instructions.isEmpty }
                    .map { RouteStep(instructions: $0.instructions,
                                     distance: $0.distance,
                                     startCoordinate: $0.polyline.coordinates.first ?? origin) }
                return RouteResult(coordinates: best.polyline.coordinates,
                                   travelTime: best.expectedTravelTime,
                                   distance: best.distance,
                                   provenance: .real,
                                   steps: steps)
            }
        } catch {
            // fall through to synthetic
        }
        return Self.synthetic(from: origin, to: destination)
    }

    /// Real alternate routes for the corridor, from MapKit only. MapKit's
    /// walking directions frequently offer just one route with no
    /// alternates — this returns however many real ones exist (often zero),
    /// rather than fabricating a straight-line "as the crow flies" path to
    /// pad out to a fixed count. A synthetic route drawn as a smooth curve
    /// through buildings looks like a real walkable option on the map, which
    /// is actively misleading for a safety app — better to show fewer, real
    /// routes than a fake one filling a safety-tier legend slot.
    func alternates(from origin: CLLocationCoordinate2D,
                    to destination: CLLocationCoordinate2D) async -> [[CLLocationCoordinate2D]] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        request.requestsAlternateRoutes = true

        let directions = MKDirections(request: request)
        guard let response = try? await directions.calculate() else { return [] }
        return Array(response.routes.dropFirst().map { $0.polyline.coordinates }.prefix(2))
    }

    // MARK: Synthetic fallback

    static func synthetic(from origin: CLLocationCoordinate2D,
                          to destination: CLLocationCoordinate2D,
                          bow: Double = 0) -> RouteResult {
        let steps = 24
        var coords: [CLLocationCoordinate2D] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            // Slight sinusoidal bow so alternates look distinct.
            let curve = sin(t * .pi) * bow
            let lat = origin.latitude + (destination.latitude - origin.latitude) * t + curve
            let lon = origin.longitude + (destination.longitude - origin.longitude) * t + curve
            coords.append(.init(latitude: lat, longitude: lon))
        }
        let distance = origin.location.distance(from: destination.location)
        // Walking ~1.35 m/s.
        return RouteResult(coordinates: coords,
                           travelTime: distance / 1.35,
                           distance: distance,
                           provenance: .simulated)
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(),
                                              count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
