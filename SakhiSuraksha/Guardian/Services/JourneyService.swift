//
//  JourneyService.swift
//  Guardian
//
//  Owns the live journey and its cached Safety Corridor, and performs
//  conservative route-deviation detection so GPS jitter never raises an alarm.
//

import Foundation
import CoreLocation
import Observation

@Observable
final class LiveJourney: Identifiable {
    let id = UUID()
    var originName: String
    var destinationName: String
    var origin: CLLocationCoordinate2D
    var destination: CLLocationCoordinate2D
    var contactName: String?
    var startedAt: Date
    var plannedDuration: TimeInterval
    var corridor: SafetyCorridor
    var status: JourneyStatus = .active

    // Live tracking
    var progress: Double = 0                 // 0...1 along the route
    var deviation: DeviationLevel = .normal
    var deviationMeters: Double = 0
    var routeProvenance: DataProvenance = .simulated
    /// Index into corridor.steps for the maneuver the user is currently
    /// approaching/on. nil until the first location update classifies it.
    var currentStepIndex: Int?

    var currentStep: RouteStep? {
        guard let currentStepIndex, corridor.steps.indices.contains(currentStepIndex) else { return nil }
        return corridor.steps[currentStepIndex]
    }

    /// Distance from the user's last-known position to the start of the
    /// step after the current one — i.e. "how far until this maneuver."
    /// Approximate: computed from route progress, not a live GPS distance,
    /// since LiveJourney doesn't hold the user's raw CLLocation.
    var distanceToNextStepMeters: Double?

    init(originName: String, destinationName: String,
         origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D,
         contactName: String?, plannedDuration: TimeInterval, corridor: SafetyCorridor) {
        self.originName = originName
        self.destinationName = destinationName
        self.origin = origin
        self.destination = destination
        self.contactName = contactName
        self.startedAt = .now
        self.plannedDuration = plannedDuration
        self.corridor = corridor
    }

    var eta: Date { startedAt.addingTimeInterval(plannedDuration) }

    var remaining: TimeInterval {
        max(0, plannedDuration * (1 - progress))
    }
}

@Observable
final class JourneyService {

    private(set) var active: LiveJourney?
    /// Consecutive readings currently beyond the on-route threshold. Used to
    /// require *persistent* deviation before escalating.
    private var consecutiveBreaches = 0

    var isActive: Bool { active?.status == .active }

    // MARK: Lifecycle

    func start(originName: String,
               destinationName: String,
               origin: CLLocationCoordinate2D,
               destination: CLLocationCoordinate2D,
               contactName: String?,
               route: RouteResult,
               alternates: [[CLLocationCoordinate2D]],
               data: SafetyDataService) async -> LiveJourney {

        // Awaited (not fire-and-forget) so checkpoints(along:) below can
        // actually snap to real nearby safe places — without this, the
        // search would still be in flight when the corridor is built and
        // every checkpoint would silently fall back to a plain waypoint.
        await data.refreshAndWait(around: origin)
        let corridor = SafetyCorridor(
            routeCoordinates: route.coordinates,
            alternateRoutes: alternates,
            destination: destination,
            expectedDuration: route.travelTime,
            checkpoints: Self.checkpoints(along: route.coordinates, safePlaces: data.safePlaces),
            nearbySafePlaces: data.safePlaces,
            incidents: data.incidents,
            cctv: data.cctv,
            zones: data.zones,
            meshNodes: [],           // real peers don't have map coordinates yet
            routeSafetyScore: Self.routeSafetyScore(incidents: data.incidents,
                                                    cctv: data.cctv),
            steps: route.steps)
        let journey = LiveJourney(originName: originName, destinationName: destinationName,
                                  origin: origin, destination: destination,
                                  contactName: contactName,
                                  plannedDuration: route.travelTime, corridor: corridor)
        journey.routeProvenance = route.provenance
        consecutiveBreaches = 0
        active = journey
        return journey
    }

    func complete() {
        active?.status = .completed
        active = nil
        consecutiveBreaches = 0
    }

    func cancel() {
        active?.status = .cancelled
        active = nil
        consecutiveBreaches = 0
    }

    // MARK: Live update

    /// Feed a new location; updates progress and deviation classification.
    @discardableResult
    func update(location: CLLocation) -> DeviationLevel {
        guard let journey = active, !journey.corridor.routeCoordinates.isEmpty else {
            return .normal
        }
        let route = journey.corridor.routeCoordinates

        // Nearest route point → distance + progress.
        var nearestIndex = 0
        var nearestDistance = Double.greatestFiniteMagnitude
        for (i, coord) in route.enumerated() {
            let d = coord.location.distance(from: location)
            if d < nearestDistance {
                nearestDistance = d
                nearestIndex = i
            }
        }
        journey.progress = route.count > 1 ? Double(nearestIndex) / Double(route.count - 1) : 0
        journey.deviationMeters = nearestDistance

        // Track persistence of breaches.
        if nearestDistance >= 75 {
            consecutiveBreaches += 1
        } else {
            consecutiveBreaches = 0
        }

        let level = Self.deviationLevel(distanceMeters: nearestDistance,
                                        consecutiveBreaches: consecutiveBreaches)
        journey.deviation = level

        // Mark checkpoints as reached.
        for i in journey.corridor.checkpoints.indices {
            if journey.corridor.checkpoints[i].coordinate.location.distance(from: location) < 60 {
                journey.corridor.checkpoints[i].reached = true
            }
        }

        updateCurrentStep(journey: journey, location: location)
        return level
    }

    /// Finds the maneuver step whose start point is closest to (but not yet
    /// passed) the user's current position, and the straight-line distance
    /// to it — the data a turn-by-turn banner needs ("Turn left in 150m").
    private func updateCurrentStep(journey: LiveJourney, location: CLLocation) {
        let steps = journey.corridor.steps
        guard !steps.isEmpty else {
            journey.currentStepIndex = nil
            journey.distanceToNextStepMeters = nil
            return
        }

        // The step whose start is nearest the user is the one they're
        // either approaching or currently executing.
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (i, step) in steps.enumerated() {
            let d = step.startCoordinate.location.distance(from: location)
            if d < bestDistance {
                bestDistance = d
                bestIndex = i
            }
        }

        // Once within 20m of a step's start, consider it "current" and look
        // ahead to the next one for the countdown distance; otherwise we're
        // still approaching bestIndex itself.
        if bestDistance < 20, bestIndex + 1 < steps.count {
            journey.currentStepIndex = bestIndex + 1
            journey.distanceToNextStepMeters = steps[bestIndex + 1].startCoordinate.location.distance(from: location)
        } else {
            journey.currentStepIndex = bestIndex
            journey.distanceToNextStepMeters = bestDistance
        }
    }

    /// The user tells us the deviation is intentional — reset the alarm.
    func acknowledgeNewRoute() {
        consecutiveBreaches = 0
        active?.deviation = .normal
    }

    // MARK: Deviation classification (pure, testable)

    /// Conservative mapping. Small distances are never dangerous, and larger
    /// distances require several consecutive readings to escalate.
    static func deviationLevel(distanceMeters d: Double, consecutiveBreaches n: Int) -> DeviationLevel {
        if d < 30 { return .normal }
        if d < 75 { return .minor }
        if d < 160 { return n >= 3 ? .cautious : .minor }
        return n >= 3 ? .alert : .cautious
    }

    // MARK: Corridor helpers

    /// Places checkpoints by actual distance along the route, not coordinate
    /// index — MapKit routes vary wildly in point density, so indexing by
    /// fraction-of-points could bunch checkpoints together on a route with
    /// few, widely-spaced vertices. Any route with at least 2 points and a
    /// non-zero length gets at least one checkpoint (the midpoint); routes
    /// over 150m get all three (25/50/75%).
    ///
    /// Each checkpoint prefers a REAL nearby safe place (shop, pharmacy,
    /// police station, etc. from live MapKit search, already fetched into
    /// `safePlaces` for the journey's corridor) within `snapRadiusMeters` of
    /// that point along the route — e.g. "Checkpoint 2 — Apollo Pharmacy" —
    /// so checkpoints double as real waypoints to duck into if needed, not
    /// just abstract progress markers. Falls back to a plain route waypoint
    /// when nothing real is nearby, honestly labelled as such.
    static func checkpoints(along route: [CLLocationCoordinate2D],
                            safePlaces: [SafePlace] = [],
                            snapRadiusMeters: Double = 150) -> [Checkpoint] {
        guard route.count >= 2 else { return [] }

        var cumulative: [Double] = [0]
        for i in 1..<route.count {
            cumulative.append(cumulative[i - 1] + route[i].location.distance(from: route[i - 1].location))
        }
        let total = cumulative.last ?? 0
        guard total > 0 else { return [] }

        func coordinate(atFraction f: Double) -> CLLocationCoordinate2D {
            let target = total * f
            guard let idx = cumulative.firstIndex(where: { $0 >= target }) else { return route.last! }
            if idx == 0 { return route[0] }
            let segStart = cumulative[idx - 1], segEnd = cumulative[idx]
            let segFraction = segEnd > segStart ? (target - segStart) / (segEnd - segStart) : 0
            let a = route[idx - 1], b = route[idx]
            return CLLocationCoordinate2D(
                latitude: a.latitude + (b.latitude - a.latitude) * segFraction,
                longitude: a.longitude + (b.longitude - a.longitude) * segFraction)
        }

        // Each real safe place can anchor at most one checkpoint, so two
        // nearby fractions don't both grab the same shop.
        var usedPlaceIDs = Set<UUID>()
        func nearestUnusedSafePlace(to point: CLLocationCoordinate2D) -> SafePlace? {
            let pointLoc = point.location
            return safePlaces
                .filter { !usedPlaceIDs.contains($0.id) }
                .compactMap { place -> (SafePlace, Double)? in
                    let d = place.coordinate.location.distance(from: pointLoc)
                    return d <= snapRadiusMeters ? (place, d) : nil
                }
                .min { $0.1 < $1.1 }?
                .0
        }

        let fractions = total > 150 ? [0.25, 0.5, 0.75] : [0.5]
        return fractions.enumerated().map { index, f in
            let point = coordinate(atFraction: f)
            if let place = nearestUnusedSafePlace(to: point) {
                usedPlaceIDs.insert(place.id)
                return Checkpoint(name: "Checkpoint \(index + 1) — \(place.name)",
                                  coordinate: place.coordinate,
                                  safePlaceType: place.type,
                                  provenance: .real)
            }
            return Checkpoint(name: "Checkpoint \(index + 1)", coordinate: point, provenance: .simulated)
        }
    }

    static func routeSafetyScore(incidents: [Incident], cctv: [CCTVEvent]) -> Int {
        let coverage = cctv.isEmpty ? 0 : cctv.map(\.coveragePercent).reduce(0, +) / cctv.count
        let base = 78 + coverage / 10
        let penalty = incidents.count * 5
        return min(100, max(30, base - penalty))
    }
}
