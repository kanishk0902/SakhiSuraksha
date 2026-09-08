//
//  ValueModels.swift
//  Guardian
//
//  Lightweight value types used across the safety features. These are the
//  transient / mock domain objects (places, signals, mesh graph, corridor).
//  Durable state lives in PersistentModels.swift (SwiftData).
//

import SwiftUI
import CoreLocation

// MARK: - Safety confidence

/// The transparent, explainable safety score.
struct SafetyConfidence: Identifiable {
    let id = UUID()
    var score: Int                 // 0...100
    var state: SafetyState
    var signals: [SafetySignal]
    var updatedAt: Date = .now

    static let unknown = SafetyConfidence(score: 50, state: .passive, signals: [])

    /// Signals that lowered the score, most impactful first.
    var negativeSignals: [SafetySignal] {
        signals.filter { !$0.isPositive }.sorted { $0.impact < $1.impact }
    }

    /// Signals that reassured the score.
    var positiveSignals: [SafetySignal] {
        signals.filter { $0.isPositive }.sorted { $0.impact > $1.impact }
    }
}

/// A single explainable contribution to the safety score.
struct SafetySignal: Identifiable {
    let id = UUID()
    var kind: SignalKind
    var label: String              // e.g. "Route deviation detected"
    var impact: Int                // +/- contribution to score
    var provenance: DataProvenance = .simulated

    var isPositive: Bool { impact >= 0 }

    var symbol: String {
        switch kind {
        case .routeAdherence:    return "point.topleft.down.to.point.bottomright.curvepath"
        case .routeDeviation:    return "arrow.triangle.branch"
        case .timeOfDay:         return "moon.stars.fill"
        case .environment:       return "leaf.fill"
        case .nearbySafePlaces:  return "shield.lefthalf.filled"
        case .cctvCoverage:      return "video.fill"
        case .crowdDensity:      return "person.3.fill"
        case .recentIncidents:   return "exclamationmark.bubble.fill"
        case .connectivity:      return "wifi"
        case .unusualMovement:   return "figure.fall"
        case .userConfirmation:  return "hand.thumbsup.fill"
        case .watchEvent:        return "applewatch"
        case .hardwareEvent:     return "sensor.tag.radiowaves.forward.fill"
        case .safeInfrastructure: return "building.2.fill"
        }
    }
}

// MARK: - Places / incidents / coverage

struct SafePlace: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var type: SafePlaceType
    var coordinate: CLLocationCoordinate2D
    var safetyScore: Int           // 0...100
    var isVerified: Bool
    var provenance: DataProvenance
    var openNow: Bool = true

    init(id: UUID = UUID(),
         name: String,
         type: SafePlaceType,
         coordinate: CLLocationCoordinate2D,
         safetyScore: Int,
         isVerified: Bool = true,
         provenance: DataProvenance = .real,
         openNow: Bool = true) {
        self.id = id
        self.name = name
        self.type = type
        self.coordinate = coordinate
        self.safetyScore = safetyScore
        self.isVerified = isVerified
        self.provenance = provenance
        self.openNow = openNow
    }

    // Codable: CLLocationCoordinate2D is not auto-Codable, so encode lat/lon manually.
    enum CodingKeys: String, CodingKey {
        case id, name, type, latitude, longitude, safetyScore, isVerified, provenance, openNow
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encode(coordinate.latitude, forKey: .latitude)
        try c.encode(coordinate.longitude, forKey: .longitude)
        try c.encode(safetyScore, forKey: .safetyScore)
        try c.encode(isVerified, forKey: .isVerified)
        try c.encode(provenance, forKey: .provenance)
        try c.encode(openNow, forKey: .openNow)
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(SafePlaceType.self, forKey: .type)
        coordinate = CLLocationCoordinate2D(latitude: try c.decode(Double.self, forKey: .latitude),
                                             longitude: try c.decode(Double.self, forKey: .longitude))
        safetyScore = try c.decode(Int.self, forKey: .safetyScore)
        isVerified = try c.decode(Bool.self, forKey: .isVerified)
        provenance = try c.decode(DataProvenance.self, forKey: .provenance)
        openNow = try c.decode(Bool.self, forKey: .openNow)
    }

    static func == (lhs: SafePlace, rhs: SafePlace) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    func distance(from location: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: location)
    }
}

/// A ranked candidate for "Get Me Somewhere Safe".
struct SafeDestination: Identifiable {
    var id: UUID { place.id }
    var place: SafePlace
    var distance: CLLocationDistance
    var rankedScore: Int           // combined ranking score 0...100

    var distanceText: String {
        distance < 1000
            ? "\(Int(distance)) m"
            : String(format: "%.1f km", distance / 1000)
    }
}

struct Incident: Identifiable {
    let id: UUID
    var type: IncidentType
    var coordinate: CLLocationCoordinate2D
    var note: String
    var reportedAt: Date
    var provenance: DataProvenance

    init(id: UUID = UUID(), type: IncidentType, coordinate: CLLocationCoordinate2D,
         note: String, reportedAt: Date = .now, provenance: DataProvenance = .simulated) {
        self.id = id
        self.type = type
        self.coordinate = coordinate
        self.note = note
        self.reportedAt = reportedAt
        self.provenance = provenance
    }
}

/// Placeholder CCTV coverage marker — clearly simulated.
struct CCTVEvent: Identifiable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    var coveragePercent: Int
    var isAnomaly: Bool
    var provenance: DataProvenance

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, coveragePercent: Int,
         isAnomaly: Bool = false, provenance: DataProvenance = .simulated) {
        self.id = id
        self.coordinate = coordinate
        self.coveragePercent = coveragePercent
        self.isAnomaly = isAnomaly
        self.provenance = provenance
    }
}

struct SafetyZone: Identifiable {
    let id: UUID
    var name: String
    var center: CLLocationCoordinate2D
    var radius: CLLocationDistance
    var score: Int                 // higher = safer
    var provenance: DataProvenance

    init(id: UUID = UUID(), name: String, center: CLLocationCoordinate2D,
         radius: CLLocationDistance, score: Int, provenance: DataProvenance = .simulated) {
        self.id = id
        self.name = name
        self.center = center
        self.radius = radius
        self.score = score
        self.provenance = provenance
    }
}

// MARK: - Journey corridor

struct Checkpoint: Identifiable {
    let id = UUID()
    var name: String
    var coordinate: CLLocationCoordinate2D
    var reached: Bool = false
    /// When this checkpoint was anchored to a real nearby safe place (a
    /// shop, pharmacy, police station, etc. from live MapKit search) rather
    /// than a plain waypoint along the route.
    var safePlaceType: SafePlaceType? = nil
    var provenance: DataProvenance = .simulated
}

/// The locally-cached bundle of everything a journey needs to remain useful
/// even when the network disappears.
struct SafetyCorridor {
    var routeCoordinates: [CLLocationCoordinate2D]
    var alternateRoutes: [[CLLocationCoordinate2D]]
    var destination: CLLocationCoordinate2D
    var expectedDuration: TimeInterval
    var checkpoints: [Checkpoint]
    var nearbySafePlaces: [SafePlace]
    var incidents: [Incident]
    var cctv: [CCTVEvent]
    var zones: [SafetyZone]
    var meshNodes: [MeshNode]
    var routeSafetyScore: Int
    var steps: [RouteStep] = []
    var cachedAt: Date = .now

    static let empty = SafetyCorridor(
        routeCoordinates: [], alternateRoutes: [], destination: .init(),
        expectedDuration: 0, checkpoints: [], nearbySafePlaces: [],
        incidents: [], cctv: [], zones: [], meshNodes: [], routeSafetyScore: 80)
}

// MARK: - Mesh graph

struct MeshNode: Identifiable {
    let id: UUID
    var name: String
    var kind: MeshNodeKind
    var hopDistance: Int           // hops from this device
    var signal: Int                // 0...100 simulated link quality
    var isReachable: Bool
    var provenance: DataProvenance

    init(id: UUID = UUID(), name: String, kind: MeshNodeKind, hopDistance: Int,
         signal: Int, isReachable: Bool = true, provenance: DataProvenance = .simulated) {
        self.id = id
        self.name = name
        self.kind = kind
        self.hopDistance = hopDistance
        self.signal = signal
        self.isReachable = isReachable
        self.provenance = provenance
    }
}

struct MeshRoute {
    var hops: [MeshNode]
    var reachesGateway: Bool
}

// MARK: - Future integration abstractions

/// An event delivered from a paired Apple Watch. Fed into the SafetyEngine.
struct WatchSafetyEvent: Identifiable, Sendable {
    enum Kind: String, Sendable { case sos, checkIn, fall, heartRateSpike, journeyState }
    let id = UUID()
    var kind: Kind
    var timestamp: Date = .now
    var confidence: Double = 1.0
}

/// A discreet event from future companion hardware (e.g. a muscle-sensor band).
struct HardwareSafetyEvent: Identifiable, Sendable {
    enum Source: String, Sendable { case muscleSensor, wearableButton, keychain }
    enum EventKind: String, Sendable { case discreetSOS, gesture, tamper }
    let id = UUID()
    var source: Source
    var eventType: EventKind
    var timestamp: Date = .now
    var confidence: Double
}

// MARK: - Help request (contact-based, not a live helper marketplace)

/// A one-shot assistance request. Guardian has no live helper-matching
/// backend — this is composed into an SMS a trusted contact must read and
/// respond to, the same way every other alert in the app works. Not
/// persisted: it exists only long enough to build the message.
struct HelpRequest: Identifiable {
    let id = UUID()
    var needType: String
    var note: String
    var coordinate: CLLocationCoordinate2D
    var createdAt: Date = .now
}

// MARK: - CLLocationCoordinate2D convenience

extension CLLocationCoordinate2D {
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    func offset(latMeters: Double, lonMeters: Double) -> CLLocationCoordinate2D {
        let dLat = latMeters / 111_320.0
        let dLon = lonMeters / (111_320.0 * cos(latitude * .pi / 180))
        return .init(latitude: latitude + dLat, longitude: longitude + dLon)
    }
}
