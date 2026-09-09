//
//  CommunityGuardianModels.swift
//  Guardian
//
//  Community Guardian: an opt-in layer of nearby verified community members
//  who can be paged during an SOS to assist — never to confront — while
//  professional emergency services remain the primary responder. Persisted
//  with SwiftData so opt-in status and in-flight requests survive restarts.
//

import Foundation
import SwiftData
import CoreLocation

// MARK: - Community Guardian profile

/// One Guardian's opt-in profile — either this device's own (isLocalUser),
/// a real peer discovered over the mesh, or a seeded demo profile
/// (isDemoSeed) used when no real peer is nearby. Never a claim of real
/// identity/first-aid/NGO verification — see GuardianVerificationLevel.label.
@Model
final class CommunityGuardian {
    @Attribute(.unique) var guardianID: UUID
    var displayName: String
    var verificationLevelRaw: String
    var availabilityRaw: String
    var capabilitiesRaw: [String]
    var latitude: Double?
    var longitude: Double?
    var lastLocationUpdate: Date?
    var activeEmergencyID: UUID?
    var organizationID: String?
    var isLocalUser: Bool
    var isDemoSeed: Bool
    var isSuspended: Bool
    var provenanceRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(guardianID: UUID = UUID(),
         displayName: String,
         verificationLevel: GuardianVerificationLevel = .community,
         availability: GuardianAvailability = .offline,
         capabilities: [GuardianCapability] = [],
         latitude: Double? = nil,
         longitude: Double? = nil,
         lastLocationUpdate: Date? = nil,
         activeEmergencyID: UUID? = nil,
         organizationID: String? = nil,
         isLocalUser: Bool = false,
         isDemoSeed: Bool = false,
         isSuspended: Bool = false,
         provenance: DataProvenance = .real) {
        self.guardianID = guardianID
        self.displayName = displayName
        self.verificationLevelRaw = verificationLevel.rawValue
        self.availabilityRaw = availability.rawValue
        self.capabilitiesRaw = capabilities.map(\.rawValue)
        self.latitude = latitude
        self.longitude = longitude
        self.lastLocationUpdate = lastLocationUpdate
        self.activeEmergencyID = activeEmergencyID
        self.organizationID = organizationID
        self.isLocalUser = isLocalUser
        self.isDemoSeed = isDemoSeed
        self.isSuspended = isSuspended
        self.provenanceRaw = provenance.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }

    var verificationLevel: GuardianVerificationLevel {
        get { GuardianVerificationLevel(rawValue: verificationLevelRaw) ?? .community }
        set { verificationLevelRaw = newValue.rawValue }
    }

    var availability: GuardianAvailability {
        get { GuardianAvailability(rawValue: availabilityRaw) ?? .offline }
        set { availabilityRaw = newValue.rawValue }
    }

    var capabilities: [GuardianCapability] {
        get { capabilitiesRaw.compactMap(GuardianCapability.init) }
        set { capabilitiesRaw = newValue.map(\.rawValue) }
    }

    var provenance: DataProvenance {
        get { DataProvenance(rawValue: provenanceRaw) ?? .real }
        set { provenanceRaw = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// A Guardian can be matched only while available, not suspended, not
    /// already tied up with another emergency, and with a known location.
    var isEligible: Bool {
        !isSuspended && availability == .available && activeEmergencyID == nil && coordinate != nil
    }
}

// MARK: - Community Guardian request

/// One notification sent to one candidate Guardian for one active emergency.
/// Deliberately carries no coordinate — only an approximate distance — so the
/// requester's exact location is never exposed before acceptance (see
/// CommunityGuardianService's privacy gating).
@Model
final class CommunityGuardianRequest {
    @Attribute(.unique) var requestID: UUID
    var emergencyID: UUID
    var guardianID: UUID
    var statusRaw: String
    var approximateDistanceMeters: Double
    var emergencyCategoryRaw: String
    var provenanceRaw: String
    var createdAt: Date
    var acceptedAt: Date?
    var completedAt: Date?
    var expiresAt: Date

    init(requestID: UUID = UUID(),
         emergencyID: UUID,
         guardianID: UUID,
         status: CommunityGuardianRequestStatus = .pending,
         approximateDistanceMeters: Double,
         emergencyCategory: EmergencySource,
         provenance: DataProvenance,
         expiresAt: Date) {
        self.requestID = requestID
        self.emergencyID = emergencyID
        self.guardianID = guardianID
        self.statusRaw = status.rawValue
        self.approximateDistanceMeters = approximateDistanceMeters
        self.emergencyCategoryRaw = emergencyCategory.rawValue
        self.provenanceRaw = provenance.rawValue
        self.createdAt = .now
        self.expiresAt = expiresAt
    }

    var status: CommunityGuardianRequestStatus {
        get { CommunityGuardianRequestStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var emergencyCategory: EmergencySource {
        get { EmergencySource(rawValue: emergencyCategoryRaw) ?? .other }
        set { emergencyCategoryRaw = newValue.rawValue }
    }

    var provenance: DataProvenance {
        get { DataProvenance(rawValue: provenanceRaw) ?? .simulated }
        set { provenanceRaw = newValue.rawValue }
    }

    var isExpired: Bool { status == .pending && .now > expiresAt }
}

// MARK: - Emergency timeline event

/// A flat, chronological log of what happened during one emergency — SOS
/// lifecycle events plus Guardian search/response events, shown together so
/// the user sees one unified timeline rather than separate unrelated logs.
@Model
final class EmergencyTimelineEvent {
    @Attribute(.unique) var eventID: UUID
    var emergencyID: UUID
    var label: String
    var timestamp: Date
    var provenanceRaw: String

    init(eventID: UUID = UUID(),
         emergencyID: UUID,
         label: String,
         timestamp: Date = .now,
         provenance: DataProvenance = .real) {
        self.eventID = eventID
        self.emergencyID = emergencyID
        self.label = label
        self.timestamp = timestamp
        self.provenanceRaw = provenance.rawValue
    }

    var provenance: DataProvenance {
        get { DataProvenance(rawValue: provenanceRaw) ?? .real }
        set { provenanceRaw = newValue.rawValue }
    }
}
