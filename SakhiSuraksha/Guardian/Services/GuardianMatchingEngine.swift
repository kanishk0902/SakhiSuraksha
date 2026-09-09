//
//  GuardianMatchingEngine.swift
//  Guardian
//
//  Pure ranking logic for Community Guardian matching — a function of its
//  input, no SwiftData/mesh access, mirroring how SafetyEngine/RiskEngine keep
//  scoring logic separate from orchestration so it stays testable in isolation.
//

import Foundation
import CoreLocation

struct GuardianMatchCandidate {
    let guardian: CommunityGuardian
    let distanceMeters: Double
}

struct GuardianMatchRequest {
    var emergencyCoordinate: CLLocationCoordinate2D
    var emergencyCategory: EmergencySource
    var radiusMeters: Double
    /// Guardians already notified/declined for this emergency — never
    /// re-notified within the same search.
    var excludedGuardianIDs: Set<UUID> = []
}

struct GuardianMatchingEngine {

    /// Returns up to `limit` eligible candidates within radius, best first.
    /// Callers control the "never notify everyone" cap via `limit`.
    func rank(candidates: [CommunityGuardian],
              for request: GuardianMatchRequest,
              limit: Int = 3) -> [GuardianMatchCandidate] {
        let emergencyLoc = CLLocation(latitude: request.emergencyCoordinate.latitude,
                                       longitude: request.emergencyCoordinate.longitude)

        let scored: [(candidate: GuardianMatchCandidate, score: Double)] = candidates.compactMap { guardian in
            guard guardian.isEligible,
                  !request.excludedGuardianIDs.contains(guardian.guardianID),
                  let coordinate = guardian.coordinate else { return nil }

            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: emergencyLoc)
            guard distance <= request.radiusMeters else { return nil }

            let candidate = GuardianMatchCandidate(guardian: guardian, distanceMeters: distance)
            return (candidate, score(for: guardian, distanceMeters: distance, category: request.emergencyCategory))
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.candidate)
    }

    /// Higher is better. Distance dominates (closer = higher, floors at 0
    /// beyond 2km); capability match against the emergency category and
    /// verification level each add a smaller weighted bonus.
    private func score(for guardian: CommunityGuardian, distanceMeters: Double, category: EmergencySource) -> Double {
        var value = max(0, 2000 - distanceMeters)

        if preferredCapabilities(for: category).contains(where: guardian.capabilities.contains) {
            value += 500
        }

        switch guardian.verificationLevel {
        case .verified, .organization: value += 200
        case .community: break
        }

        return value
    }

    private func preferredCapabilities(for category: EmergencySource) -> [GuardianCapability] {
        switch category {
        case .medicalSOS:
            return [.medicalAssistance, .firstAid]
        case .manual, .discreetPhrase, .journeyTimeout, .appleWatch, .fallDetection, .other:
            return [.security, .generalAssistance]
        }
    }
}
