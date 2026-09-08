//
//  PersistentModels.swift
//  Guardian
//
//  Durable local state persisted with SwiftData. Emergency packets, contacts,
//  the user profile and evidence metadata survive app restarts so the safety
//  network works offline and after a crash.
//

import Foundation
import SwiftData
import CoreLocation

// MARK: - User profile

@Model
final class UserProfile {
    var name: String
    var bloodType: String
    var medicalNotes: String
    var emergencyMessage: String
    var shareMedicalInEmergency: Bool
    var createdAt: Date

    init(name: String = "",
         bloodType: String = "",
         medicalNotes: String = "",
         emergencyMessage: String = "I need help. This is an automated Guardian alert with my location.",
         shareMedicalInEmergency: Bool = true) {
        self.name = name
        self.bloodType = bloodType
        self.medicalNotes = medicalNotes
        self.emergencyMessage = emergencyMessage
        self.shareMedicalInEmergency = shareMedicalInEmergency
        self.createdAt = .now
    }
}

// MARK: - Emergency contact

@Model
final class EmergencyContact {
    var name: String
    var phone: String
    var relationship: String
    var isPrimary: Bool
    var notifyOnJourney: Bool
    var createdAt: Date

    init(name: String,
         phone: String,
         relationship: String = "",
         isPrimary: Bool = false,
         notifyOnJourney: Bool = true) {
        self.name = name
        self.phone = phone
        self.relationship = relationship
        self.isPrimary = isPrimary
        self.notifyOnJourney = notifyOnJourney
        self.createdAt = .now
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

// MARK: - Emergency packet

/// The store-and-forward safety payload. Persisted so it survives restarts and
/// can be relayed when any communication path becomes available.
@Model
final class EmergencyPacket {
    @Attribute(.unique) var packetID: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var safetyStateRaw: String
    var riskScore: Int
    var message: String
    var senderID: String
    var ttl: Int                    // remaining hop budget
    var deliveryStateRaw: String
    var hopCount: Int
    var sourceRaw: String = EmergencySource.manual.rawValue

    init(packetID: UUID = UUID(),
         timestamp: Date = .now,
         latitude: Double,
         longitude: Double,
         safetyState: SafetyState,
         riskScore: Int,
         message: String,
         senderID: String,
         ttl: Int = 8,
         deliveryState: PacketDeliveryState = .created,
         hopCount: Int = 0,
         source: EmergencySource = .manual) {
        self.packetID = packetID
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.safetyStateRaw = safetyState.rawValue
        self.riskScore = riskScore
        self.message = message
        self.senderID = senderID
        self.ttl = ttl
        self.deliveryStateRaw = deliveryState.rawValue
        self.hopCount = hopCount
        self.sourceRaw = source.rawValue
    }

    var safetyState: SafetyState {
        get { SafetyState(rawValue: safetyStateRaw) ?? .passive }
        set { safetyStateRaw = newValue.rawValue }
    }

    var source: EmergencySource {
        get { EmergencySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var deliveryState: PacketDeliveryState {
        get { PacketDeliveryState(rawValue: deliveryStateRaw) ?? .created }
        set { deliveryStateRaw = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    /// A packet is dead once its hop budget is exhausted.
    var isExpired: Bool { ttl <= 0 }
}

// MARK: - Emergency evidence metadata

/// Metadata only — the app never silently records. A capture always has an
/// explicit start time and visible indicator managed by the UI.
@Model
final class EmergencyEvidence {
    @Attribute(.unique) var evidenceID: UUID
    var kindRaw: String
    var startedAt: Date
    var durationSeconds: Double
    var latitude: Double
    var longitude: Double
    var safetyStateRaw: String
    var journeyID: UUID?
    var uploaded: Bool
    var localFileName: String?

    init(evidenceID: UUID = UUID(),
         kind: EvidenceKind,
         startedAt: Date = .now,
         durationSeconds: Double = 0,
         latitude: Double,
         longitude: Double,
         safetyState: SafetyState,
         journeyID: UUID? = nil,
         uploaded: Bool = false,
         localFileName: String? = nil) {
        self.evidenceID = evidenceID
        self.kindRaw = kind.rawValue
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.latitude = latitude
        self.longitude = longitude
        self.safetyStateRaw = safetyState.rawValue
        self.journeyID = journeyID
        self.uploaded = uploaded
        self.localFileName = localFileName
    }

    var kind: EvidenceKind {
        get { EvidenceKind(rawValue: kindRaw) ?? .audio }
        set { kindRaw = newValue.rawValue }
    }

    var safetyState: SafetyState {
        get { SafetyState(rawValue: safetyStateRaw) ?? .passive }
        set { safetyStateRaw = newValue.rawValue }
    }
}

// MARK: - Persisted relay packet

/// Low-level MPC transport envelope persisted for store-and-forward.
/// Separate from EmergencyPacket (the semantic SOS record). Deleted once delivered.
@Model
final class PersistedRelayPacket {
    @Attribute(.unique) var packetID: String
    var data: Data          // JSON-encoded RelayPacket
    var createdAt: Date

    init(packetID: String, data: Data, createdAt: Date = .now) {
        self.packetID = packetID
        self.data = data
        self.createdAt = createdAt
    }
}

// MARK: - Journey history record

/// A completed / cancelled journey kept for history. The live journey is held
/// in memory by JourneyService.
@Model
final class JourneyRecord {
    @Attribute(.unique) var journeyID: UUID
    var originName: String
    var destinationName: String
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String
    var contactName: String?

    init(journeyID: UUID = UUID(),
         originName: String,
         destinationName: String,
         startedAt: Date = .now,
         endedAt: Date? = nil,
         status: JourneyStatus = .active,
         contactName: String? = nil) {
        self.journeyID = journeyID
        self.originName = originName
        self.destinationName = destinationName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.statusRaw = status.rawValue
        self.contactName = contactName
    }

    var status: JourneyStatus {
        get { JourneyStatus(rawValue: statusRaw) ?? .completed }
        set { statusRaw = newValue.rawValue }
    }
}

// MARK: - Medical SOS event

@Model
final class MedicalSOSEvent {
    @Attribute(.unique) var eventID: UUID
    var emergencyTypeRaw: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date
    var resolvedAt: Date?
    var notes: String

    init(eventID: UUID = UUID(),
         emergencyType: MedicalEmergencyType,
         latitude: Double,
         longitude: Double,
         notes: String = "") {
        self.eventID = eventID
        self.emergencyTypeRaw = emergencyType.rawValue
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = .now
        self.notes = notes
    }

    var emergencyType: MedicalEmergencyType {
        get { MedicalEmergencyType(rawValue: emergencyTypeRaw) ?? .other }
        set { emergencyTypeRaw = newValue.rawValue }
    }

    var isResolved: Bool { resolvedAt != nil }
}

// MARK: - Community safety report

@Model
final class CommunityReport {
    @Attribute(.unique) var reportID: UUID
    var reportTypeRaw: String
    var latitude: Double
    var longitude: Double
    var note: String
    var createdAt: Date
    var isAnonymous: Bool

    init(reportID: UUID = UUID(),
         reportType: CommunityReportType,
         latitude: Double,
         longitude: Double,
         note: String = "",
         isAnonymous: Bool = true) {
        self.reportID = reportID
        self.reportTypeRaw = reportType.rawValue
        self.latitude = latitude
        self.longitude = longitude
        self.note = note
        self.createdAt = .now
        self.isAnonymous = isAnonymous
    }

    var reportType: CommunityReportType {
        get { CommunityReportType(rawValue: reportTypeRaw) ?? .other }
        set { reportTypeRaw = newValue.rawValue }
    }
}

// MARK: - Discreet SOS settings

@Model
final class DiscreetSOSSettings {
    var isEnabled: Bool
    var phrase: String
    var activationTimeoutSeconds: Int
    var autoShareLocation: Bool
    var updatedAt: Date

    init(isEnabled: Bool = false,
         phrase: String = "",
         activationTimeoutSeconds: Int = 10,
         autoShareLocation: Bool = true) {
        self.isEnabled = isEnabled
        self.phrase = phrase
        self.activationTimeoutSeconds = activationTimeoutSeconds
        self.autoShareLocation = autoShareLocation
        self.updatedAt = .now
    }
}
