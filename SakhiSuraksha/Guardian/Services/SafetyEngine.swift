//
//  SafetyEngine.swift
//  Guardian
//
//  Transparent, explainable safety scoring. Every point of the score is traced
//  to a concrete SafetySignal so the UI can always answer "why did this change?".
//  The engine is a pure function of its input context, which keeps it testable
//  and lets a real ML model replace it later behind the same interface.
//

import Foundation

/// The snapshot of everything the engine reasons about. Built by AppModel from
/// the live services; also constructed directly in unit tests.
/// All fields are populated from real device data only — no hardcoded values.
struct SafetyContext {
    var date: Date = .now
    var connectivity: ConnectivityState = .online
    var onJourney: Bool = false
    var deviation: DeviationLevel = .normal
    var nearbySafePlaceCount: Int = 0
    var nearestSafePlaceMeters: Double? = nil
    // cctvCoveragePercent: only non-zero when a real CCTVDataProvider is wired.
    var cctvCoveragePercent: Int = 0
    // nearbyIncidentCount: only non-zero when a real SafetyIncidentProvider is wired.
    var nearbyIncidentCount: Int = 0
    var unusualMovement: Bool = false
    var userConfirmedSafe: Bool = false
    var watchEvent: WatchSafetyEvent? = nil
    var hardwareEvent: HardwareSafetyEvent? = nil
    var explicitEmergency: Bool = false
}

@Observable
final class SafetyEngine {

    /// Produce a fully explained safety confidence from a context.
    func evaluate(_ context: SafetyContext) -> SafetyConfidence {
        var signals: [SafetySignal] = []

        // Baseline environment: night hours reduce confidence.
        let hour = Calendar.current.component(.hour, from: context.date)
        if hour >= 22 || hour < 5 {
            signals.append(.init(kind: .timeOfDay, label: "Late night hours (10pm–5am)", impact: -15))
        } else if hour >= 20 {
            signals.append(.init(kind: .timeOfDay, label: "Evening hours", impact: -6))
        } else if hour >= 6 && hour < 20 {
            signals.append(.init(kind: .timeOfDay, label: "Daytime", impact: +10))
        }

        // Route adherence / deviation.
        switch context.deviation {
        case .normal:
            if context.onJourney {
                signals.append(.init(kind: .routeAdherence, label: "On planned route", impact: +12))
            }
        case .minor:
            signals.append(.init(kind: .routeDeviation, label: "Minor route change", impact: -8))
        case .cautious:
            signals.append(.init(kind: .routeDeviation, label: "Moderate route deviation", impact: -20))
        case .alert:
            signals.append(.init(kind: .routeDeviation, label: "Route deviation detected", impact: -32))
        case .emergency:
            signals.append(.init(kind: .routeDeviation, label: "Severe route deviation", impact: -45))
        }

        // Nearby safe places.
        if let meters = context.nearestSafePlaceMeters {
            if meters < 200 {
                signals.append(.init(kind: .nearbySafePlaces,
                                     label: "Safe place \(Int(meters)) m away", impact: +18))
            } else if meters < 500 {
                signals.append(.init(kind: .nearbySafePlaces,
                                     label: "Safe place \(Int(meters)) m away", impact: +12))
            } else if meters < 1000 {
                signals.append(.init(kind: .nearbySafePlaces,
                                     label: "Nearest safe place \(Int(meters)) m away", impact: +5))
            } else {
                signals.append(.init(kind: .nearbySafePlaces,
                                     label: "No safe places within 1 km", impact: -8))
            }
        } else {
            signals.append(.init(kind: .nearbySafePlaces, label: "Safe places unknown", impact: -5))
        }
        if context.nearbySafePlaceCount >= 4 {
            signals.append(.init(kind: .safeInfrastructure,
                                 label: "\(context.nearbySafePlaceCount) safe places nearby", impact: +8))
        }

        // CCTV coverage.
        if context.cctvCoveragePercent >= 60 {
            signals.append(.init(kind: .cctvCoverage,
                                 label: "CCTV coverage available", impact: +6))
        } else if context.cctvCoveragePercent > 0 {
            signals.append(.init(kind: .cctvCoverage,
                                 label: "Limited CCTV coverage", impact: -3))
        }

        // Incidents.
        if context.nearbyIncidentCount > 0 {
            signals.append(.init(kind: .recentIncidents,
                                 label: "\(context.nearbyIncidentCount) reported nearby",
                                 impact: -6 * min(context.nearbyIncidentCount, 3)))
        }

        // Connectivity.
        switch context.connectivity {
        case .online:
            signals.append(.init(kind: .connectivity, label: "WiFi connected", impact: +8, provenance: .real))
        case .cellular:
            signals.append(.init(kind: .connectivity, label: "Cellular connected", impact: +6, provenance: .real))
        case .mesh:
            signals.append(.init(kind: .connectivity, label: "Mesh relay only", impact: -8))
        case .offline:
            signals.append(.init(kind: .connectivity, label: "No network — can't send alerts", impact: -18))
        }

        // Movement anomaly.
        if context.unusualMovement {
            signals.append(.init(kind: .unusualMovement, label: "Unusual movement pattern", impact: -14))
        }

        // Explicit user reassurance.
        if context.userConfirmedSafe {
            signals.append(.init(kind: .userConfirmation, label: "You confirmed you're safe", impact: +18))
        }

        // Watch / hardware events.
        if let watch = context.watchEvent {
            switch watch.kind {
            case .sos:
                signals.append(.init(kind: .watchEvent, label: "Watch SOS received", impact: -60,
                                     provenance: .future))
            case .fall:
                signals.append(.init(kind: .watchEvent, label: "Possible fall detected", impact: -22,
                                     provenance: .future))
            case .heartRateSpike:
                signals.append(.init(kind: .watchEvent, label: "Elevated heart rate", impact: -10,
                                     provenance: .future))
            case .checkIn:
                signals.append(.init(kind: .watchEvent, label: "Watch check-in: safe", impact: +12,
                                     provenance: .future))
            case .journeyState:
                break
            }
        }
        if let hw = context.hardwareEvent, hw.eventType == .discreetSOS {
            signals.append(.init(kind: .hardwareEvent, label: "Discreet hardware SOS", impact: -60,
                                 provenance: .future))
        }

        // Compute score.
        let base = 50
        let raw = base + signals.reduce(0) { $0 + $1.impact }
        let score = min(100, max(0, raw))

        // Map score → state, then take the most severe of score/deviation/events.
        var state = Self.state(forScore: score)
        state = Self.moreSevere(state, context.deviation.mappedState)
        if context.explicitEmergency
            || context.watchEvent?.kind == .sos
            || context.hardwareEvent?.eventType == .discreetSOS {
            state = .emergency
        }

        return SafetyConfidence(score: score, state: state, signals: signals)
    }

    static func state(forScore score: Int) -> SafetyState {
        switch score {
        case 72...:   return .passive
        case 48..<72: return .cautious
        default:      return .alert
        }
    }

    static func moreSevere(_ a: SafetyState, _ b: SafetyState) -> SafetyState {
        a.severity >= b.severity ? a : b
    }
}

// MARK: - Risk engine (state transitions & escalation rules)

/// Handles time-based escalation such as unanswered check-ins. Deliberately
/// conservative: a non-response raises caution, never jumps straight to emergency.
@Observable
final class RiskEngine {

    /// How many unanswered check-ins before each escalation step.
    var stepsToCautious = 1
    var stepsToAlert = 2

    /// Determine the state after `unansweredCheckIns` missed prompts, starting
    /// from `current`. Emergency is only reachable via explicit confirmation.
    func escalatedState(from current: SafetyState, unansweredCheckIns: Int) -> SafetyState {
        guard unansweredCheckIns > 0 else { return current }
        if unansweredCheckIns >= stepsToAlert {
            return SafetyEngine.moreSevere(current, .alert)
        }
        if unansweredCheckIns >= stepsToCautious {
            return SafetyEngine.moreSevere(current, .cautious)
        }
        return current
    }

    /// Whether a change warrants proactively prompting the user.
    func shouldPromptCheckIn(previous: SafetyState, next: SafetyState) -> Bool {
        next.severity > previous.severity && next.severity >= SafetyState.cautious.severity
    }
}
