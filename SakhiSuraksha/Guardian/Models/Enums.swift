//
//  Enums.swift
//  Guardian
//
//  Core domain enumerations shared across features.
//

import SwiftUI

// MARK: - Safety state

/// The always-available safety posture of the app.
enum SafetyState: String, Codable, CaseIterable, Identifiable, Sendable {
    case passive
    case cautious
    case alert
    case emergency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passive:   return "SAFE"
        case .cautious:  return "CAUTIOUS"
        case .alert:     return "ALERT"
        case .emergency: return "EMERGENCY"
        }
    }

    var subtitle: String {
        switch self {
        case .passive:   return "Passive safety layer active"
        case .cautious:  return "Elevated awareness"
        case .alert:     return "Something needs your attention"
        case .emergency: return "Emergency response active"
        }
    }

    var symbol: String {
        switch self {
        case .passive:   return "checkmark.shield.fill"
        case .cautious:  return "exclamationmark.shield.fill"
        case .alert:     return "exclamationmark.triangle.fill"
        case .emergency: return "sos"
        }
    }

    var color: Color {
        switch self {
        case .passive:   return GuardianTheme.safe
        case .cautious:  return GuardianTheme.caution
        case .alert:     return GuardianTheme.alert
        case .emergency: return GuardianTheme.emergency
        }
    }

    /// Ordering used when deciding whether to escalate/de-escalate.
    var severity: Int {
        switch self {
        case .passive:   return 0
        case .cautious:  return 1
        case .alert:     return 2
        case .emergency: return 3
        }
    }
}

// MARK: - Connectivity

enum ConnectivityState: String, Codable, CaseIterable, Sendable {
    case online
    case cellular
    case offline
    case mesh

    var title: String {
        switch self {
        case .online:   return "Online"
        case .cellular: return "Cellular"
        case .offline:  return "Offline"
        case .mesh:     return "Mesh"
        }
    }

    var symbol: String {
        switch self {
        case .online:   return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .offline:  return "wifi.slash"
        case .mesh:     return "point.3.connected.trianglepath.dotted"
        }
    }

    var color: Color {
        switch self {
        case .online:   return GuardianTheme.safe
        case .cellular: return GuardianTheme.accent
        case .offline:  return GuardianTheme.alert
        case .mesh:     return GuardianTheme.caution
        }
    }

    /// Whether a live two-way internet path exists.
    var hasInternet: Bool { self == .online || self == .cellular }
}

// MARK: - Journey

enum JourneyStatus: String, Codable, Sendable {
    case planning
    case active
    case completed
    case cancelled
}

/// Route-deviation classification. Deliberately conservative so that tiny GPS
/// jitter never triggers danger.
enum DeviationLevel: String, Codable, Sendable {
    case normal
    case minor
    case cautious
    case alert
    case emergency

    var title: String {
        switch self {
        case .normal:    return "On route"
        case .minor:     return "Minor deviation"
        case .cautious:  return "Moderate deviation"
        case .alert:     return "Significant deviation"
        case .emergency: return "Emergency"
        }
    }

    var mappedState: SafetyState {
        switch self {
        case .normal, .minor: return .passive
        case .cautious:       return .cautious
        case .alert:          return .alert
        case .emergency:      return .emergency
        }
    }
}

// MARK: - Places & incidents

enum SafePlaceType: String, Codable, CaseIterable, Sendable {
    case police
    case hospital
    case transit
    case business
    case publicBuilding
    case safeSpot

    var title: String {
        switch self {
        case .police:         return "Police Station"
        case .hospital:       return "Hospital"
        case .transit:        return "Transit Station"
        case .business:       return "Verified Business"
        case .publicBuilding: return "Public Building"
        case .safeSpot:       return "Safe Place"
        }
    }

    var symbol: String {
        switch self {
        case .police:         return "building.columns.fill"
        case .hospital:       return "cross.case.fill"
        case .transit:        return "tram.fill"
        case .business:       return "storefront.fill"
        case .publicBuilding: return "building.2.fill"
        case .safeSpot:       return "shield.lefthalf.filled"
        }
    }

    var tint: Color {
        switch self {
        case .police:         return .blue
        case .hospital:       return .red
        case .transit:        return .teal
        case .business:       return .purple
        case .publicBuilding: return .indigo
        case .safeSpot:       return GuardianTheme.safe
        }
    }
}

enum IncidentType: String, Codable, CaseIterable, Sendable {
    case poorLighting
    case harassmentReport
    case isolatedArea
    case construction
    case crowdSurge

    var title: String {
        switch self {
        case .poorLighting:     return "Poor lighting"
        case .harassmentReport: return "Reported incident"
        case .isolatedArea:     return "Isolated area"
        case .construction:     return "Construction / diversion"
        case .crowdSurge:       return "Crowd congestion"
        }
    }

    var symbol: String {
        switch self {
        case .poorLighting:     return "lightbulb.slash.fill"
        case .harassmentReport: return "exclamationmark.bubble.fill"
        case .isolatedArea:     return "figure.walk.motion"
        case .construction:     return "cone.fill"
        case .crowdSurge:       return "person.3.fill"
        }
    }
}

// MARK: - Mesh & packets

enum PacketDeliveryState: String, Codable, CaseIterable, Sendable {
    case created
    case relaying
    case queued
    case delivered
    case failed

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .created:   return "doc.badge.plus"
        case .relaying:  return "arrow.triangle.2.circlepath"
        case .queued:    return "tray.and.arrow.down.fill"
        case .delivered: return "checkmark.circle.fill"
        case .failed:    return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .created:   return GuardianTheme.accent
        case .relaying:  return GuardianTheme.caution
        case .queued:    return .secondary
        case .delivered: return GuardianTheme.safe
        case .failed:    return GuardianTheme.emergency
        }
    }
}

enum MeshNodeKind: String, Codable, Sendable {
    case phone
    case relay
    case gateway

    var symbol: String {
        switch self {
        case .phone:   return "iphone"
        case .relay:   return "dot.radiowaves.left.and.right"
        case .gateway: return "network"
        }
    }
}

// MARK: - Data provenance

/// Communicates honestly where a piece of data comes from. Never claim REAL
/// when the value is simulated or cached.
enum DataProvenance: String, Codable, Sendable {
    case real
    case simulated
    case cached
    case offline
    case future

    var label: String {
        switch self {
        case .real:   return "Real"
        case .simulated: return "Simulated"
        case .cached: return "Cached"
        case .offline: return "Offline"
        case .future: return "Future"
        }
    }

    var tint: Color {
        switch self {
        case .real:      return GuardianTheme.safe
        case .simulated: return GuardianTheme.caution
        case .cached:    return GuardianTheme.accent
        case .offline:   return GuardianTheme.alert
        case .future:    return .secondary
        }
    }
}

// MARK: - Evidence

enum EvidenceKind: String, Codable, Sendable {
    case audio
    case video
    case photo

    var symbol: String {
        switch self {
        case .audio: return "waveform"
        case .video: return "video.fill"
        case .photo: return "camera.fill"
        }
    }
}

// MARK: - Emergency source (Watch plugs in here later)

enum EmergencySource: String, Codable, Sendable {
    case manual
    case discreetPhrase
    case medicalSOS
    case journeyTimeout
    case appleWatch      // future
    case fallDetection   // future
    case other
}

// MARK: - Medical SOS

enum MedicalEmergencyType: String, Codable, CaseIterable, Sendable {
    case injury
    case fainting
    case heavyBleeding
    case pregnancyEmergency
    case severePain
    case breathingDifficulty
    case burn
    case other

    var title: String {
        switch self {
        case .injury:               return "Injury"
        case .fainting:             return "Fainting"
        case .heavyBleeding:        return "Heavy Bleeding"
        case .pregnancyEmergency:   return "Pregnancy Emergency"
        case .severePain:           return "Severe Pain"
        case .breathingDifficulty:  return "Breathing Difficulty"
        case .burn:                 return "Burn"
        case .other:                return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .injury:               return "bandage.fill"
        case .fainting:             return "figure.fall"
        case .heavyBleeding:        return "drop.fill"
        case .pregnancyEmergency:   return "figure.2.and.child.holdinghands"
        case .severePain:           return "bolt.heart.fill"
        case .breathingDifficulty:  return "lungs.fill"
        case .burn:                 return "flame.fill"
        case .other:                return "cross.case.fill"
        }
    }

    var color: Color {
        switch self {
        case .pregnancyEmergency:   return .pink
        case .heavyBleeding, .burn: return GuardianTheme.emergency
        case .breathingDifficulty:  return .blue
        default:                    return GuardianTheme.alert
        }
    }
}

// MARK: - Period emergency

enum PeriodNeedType: String, Codable, CaseIterable, Identifiable, Sendable {
    case pads
    case tampons
    case pharmacy
    case washroom
    case water
    case hygiene
    case requestAssistance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pads:               return "Pads"
        case .tampons:            return "Tampons"
        case .pharmacy:           return "Pharmacy"
        case .washroom:           return "Washroom"
        case .water:              return "Water"
        case .hygiene:            return "Hygiene"
        case .requestAssistance:  return "Request Assistance"
        }
    }

    var symbol: String {
        switch self {
        case .pads, .tampons:     return "drop.fill"
        case .pharmacy:           return "cross.case.fill"
        case .washroom:           return "figure.dress.line.vertical.figure"
        case .water:              return "drop.circle.fill"
        case .hygiene:            return "hands.sparkles.fill"
        case .requestAssistance:  return "hand.raised.fill"
        }
    }
}

// MARK: - I Need Help

enum HelpNeedType: String, Codable, CaseIterable, Identifiable, Sendable {
    case periodSupplies
    case washroom
    case water
    case firstAid
    case medicine
    case transport
    case medicalHelp
    case feelingUnsafe
    case accompaniment
    case safeHaven

    var id: String { rawValue }

    var title: String {
        switch self {
        case .periodSupplies:  return "Period Supplies"
        case .washroom:        return "Washroom"
        case .water:           return "Water"
        case .firstAid:        return "First Aid"
        case .medicine:        return "Medicine"
        case .transport:       return "Transport"
        case .medicalHelp:     return "Medical Help"
        case .feelingUnsafe:   return "Feeling Unsafe"
        case .accompaniment:   return "Need Accompaniment"
        case .safeHaven:       return "Find Safe Haven"
        }
    }

    var symbol: String {
        switch self {
        case .periodSupplies:  return "drop.fill"
        case .washroom:        return "figure.dress.line.vertical.figure"
        case .water:           return "drop.circle.fill"
        case .firstAid:        return "cross.case.fill"
        case .medicine:        return "pills.fill"
        case .transport:       return "car.fill"
        case .medicalHelp:     return "stethoscope"
        case .feelingUnsafe:   return "exclamationmark.shield.fill"
        case .accompaniment:   return "person.2.fill"
        case .safeHaven:       return "storefront.fill"
        }
    }

    var color: Color {
        switch self {
        case .feelingUnsafe:   return GuardianTheme.emergency
        case .medicalHelp:     return GuardianTheme.alert
        case .firstAid:        return GuardianTheme.alert
        default:               return GuardianTheme.accent
        }
    }
}

// MARK: - Safe Haven type

enum SafeHavenType: String, Codable, CaseIterable, Identifiable, Sendable {
    case pharmacy
    case hospital
    case policeStation
    case cafe
    case restaurant
    case shop
    case college
    case securityBooth
    case ngo
    case governmentCentre
    case petrolPump
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pharmacy:          return "Pharmacy"
        case .hospital:          return "Hospital"
        case .policeStation:     return "Police Station"
        case .cafe:              return "Café"
        case .restaurant:        return "Restaurant"
        case .shop:              return "Shop"
        case .college:           return "College"
        case .securityBooth:     return "Security Booth"
        case .ngo:               return "NGO"
        case .governmentCentre:  return "Government Centre"
        case .petrolPump:        return "Petrol Pump"
        case .other:             return "Safe Place"
        }
    }

    var symbol: String {
        switch self {
        case .pharmacy:          return "cross.case.fill"
        case .hospital:          return "cross.fill"
        case .policeStation:     return "building.columns.fill"
        case .cafe, .restaurant: return "cup.and.saucer.fill"
        case .shop:              return "storefront.fill"
        case .college:           return "graduationcap.fill"
        case .securityBooth:     return "person.badge.shield.checkmark.fill"
        case .ngo:               return "heart.fill"
        case .governmentCentre:  return "building.2.fill"
        case .petrolPump:        return "fuelpump.fill"
        case .other:             return "shield.lefthalf.filled"
        }
    }

    var tint: Color {
        switch self {
        case .pharmacy, .hospital: return .red
        case .policeStation:       return .blue
        case .ngo:                 return .pink
        case .governmentCentre:    return .indigo
        default:                   return GuardianTheme.safe
        }
    }
}

// MARK: - Community report

enum CommunityReportType: String, Codable, CaseIterable, Identifiable, Sendable {
    case poorLighting
    case harassment
    case stalking
    case unsafeRoad
    case unsafeTransport
    case lackOfFacilities
    case isolatedArea
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .poorLighting:       return "Poor Lighting"
        case .harassment:         return "Harassment"
        case .stalking:           return "Stalking / Following"
        case .unsafeRoad:         return "Unsafe Road"
        case .unsafeTransport:    return "Unsafe Transport"
        case .lackOfFacilities:   return "Lack of Facilities"
        case .isolatedArea:       return "Isolated Area"
        case .other:              return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .poorLighting:       return "lightbulb.slash.fill"
        case .harassment:         return "exclamationmark.bubble.fill"
        case .stalking:           return "figure.walk.motion"
        case .unsafeRoad:         return "cone.fill"
        case .unsafeTransport:    return "car.fill"
        case .lackOfFacilities:   return "xmark.circle.fill"
        case .isolatedArea:       return "moon.fill"
        case .other:              return "flag.fill"
        }
    }
}

// MARK: - Community Guardian

/// How a Guardian's status was established. No real identity/first-aid/NGO
/// verification backend exists yet — every level is honestly labeled as
/// prototype/demo verification, never claimed as real-world certification.
enum GuardianVerificationLevel: String, Codable, CaseIterable, Sendable {
    case community
    case verified
    case organization

    var title: String {
        switch self {
        case .community:    return "Community Guardian"
        case .verified:     return "Verified Guardian"
        case .organization: return "Organization Guardian"
        }
    }

    /// Always includes an honest verification-source disclaimer — this
    /// prototype has no real identity/certification backend.
    var label: String {
        switch self {
        case .community:    return "\(title) (Prototype verification)"
        case .verified:     return "\(title) (Demo verified)"
        case .organization: return "\(title) (Demo verified)"
        }
    }

    var symbol: String {
        switch self {
        case .community:    return "person.fill"
        case .verified:     return "checkmark.seal.fill"
        case .organization: return "building.2.fill"
        }
    }
}

enum GuardianAvailability: String, Codable, Sendable {
    case available
    case offline
    case responding

    var title: String {
        switch self {
        case .available:  return "Available"
        case .offline:    return "Offline"
        case .responding: return "Responding"
        }
    }

    var color: Color {
        switch self {
        case .available:  return GuardianTheme.safe
        case .offline:    return .secondary
        case .responding: return GuardianTheme.caution
        }
    }
}

enum GuardianCapability: String, Codable, CaseIterable, Identifiable, Sendable {
    case firstAid
    case medicalAssistance
    case security
    case collegeSecurity
    case ngoVolunteer
    case transportAssistance
    case generalAssistance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstAid:             return "First Aid"
        case .medicalAssistance:    return "Medical Assistance"
        case .security:             return "Security"
        case .collegeSecurity:      return "College Security"
        case .ngoVolunteer:         return "NGO Volunteer"
        case .transportAssistance:  return "Transport Assistance"
        case .generalAssistance:    return "General Assistance"
        }
    }

    var symbol: String {
        switch self {
        case .firstAid:             return "cross.case.fill"
        case .medicalAssistance:    return "stethoscope"
        case .security:             return "shield.lefthalf.filled"
        case .collegeSecurity:      return "graduationcap.fill"
        case .ngoVolunteer:         return "heart.fill"
        case .transportAssistance:  return "car.fill"
        case .generalAssistance:    return "hand.raised.fill"
        }
    }
}

enum CommunityGuardianRequestStatus: String, Codable, Sendable {
    case pending
    case accepted
    case declined
    case expired
    case completed
    case cancelled

    var title: String { rawValue.capitalized }
}

/// User-facing progress of a Guardian search for one active emergency.
/// Not persisted — derived fresh each time from in-memory service state, since
/// it only has meaning for the duration of one active emergency.
enum CommunityGuardianFlowState: Sendable, Equatable {
    case idle
    case searching
    case found
    case responding
    case assisting
    case completed
    case failed

    var title: String {
        switch self {
        case .idle:       return ""
        case .searching:  return "No verified Guardians found yet."
        case .found:      return "Verified Guardians nearby."
        case .responding: return "A verified Guardian has accepted the request."
        case .assisting:  return "Guardian has indicated they are assisting."
        case .completed:  return "Community assistance completed."
        case .failed:     return "No Guardian was available."
        }
    }
}

// MARK: - Signals

enum SignalKind: String, Codable, Sendable {
    case routeAdherence
    case routeDeviation
    case timeOfDay
    case environment
    case nearbySafePlaces
    case cctvCoverage
    case crowdDensity
    case recentIncidents
    case connectivity
    case unusualMovement
    case userConfirmation
    case watchEvent
    case hardwareEvent
    case safeInfrastructure
}
