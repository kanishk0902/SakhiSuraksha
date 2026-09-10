//
//  SafetyEngine.swift
//  Guardian
//
//  The safety score is the real ML model's output (the Jaipur street-segment
//  RandomForest in ml/, fed via AppModel/SafeRoutingService) — nothing else
//  contributes to the number. There is deliberately no blend with route
//  deviation, nearby-safe-place distance, connectivity, or any other
//  heuristic guess; those were arbitrary point values, not measured signals,
//  and mixing them into "the safety score" made it look precise while
//  actually being invented. When the ML score isn't available (outside the
//  model's Jaipur coverage, offline, or not yet fetched), there IS no score
//  — the UI must show that honestly rather than falling back to a guess.
//
//  The one thing that still overrides the score is a genuine active
//  emergency (explicit SOS, Watch SOS, discreet hardware SOS) — that's a
//  real, already-happened event, not a predictive heuristic, so it forces
//  the safety STATE to .emergency regardless of what the area score says.
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
    /// 0-100 ML-predicted safety score for the user's current location, from
    /// the Jaipur street-segment model (SafeRoutingService.fetchLocationSafety)
    /// — nil whenever it isn't available (outside model coverage, offline, or
    /// not yet fetched). Replaces the old hand-tuned time-of-day guess
    /// ("+10 for daytime") with a real, place-specific signal; when nil, NO
    /// signal is added rather than falling back to a guess.
    var mlAreaSafetyScore: Int? = nil
}

@Observable
final class SafetyEngine {

    /// Produce a safety confidence purely from the ML area-safety score.
    /// No other signal contributes to the number — see this file's header
    /// for why the old blended heuristics were removed.
    func evaluate(_ context: SafetyContext) -> SafetyConfidence {
        var signals: [SafetySignal] = []

        // The ML score IS the score — not one signal among several. When
        // it's nil (outside coverage, offline, not yet fetched), there is
        // genuinely no score to show; the UI is responsible for displaying
        // that honestly rather than this engine inventing a fallback number.
        let score = context.mlAreaSafetyScore ?? 50
        if let mlScore = context.mlAreaSafetyScore {
            signals.append(.init(kind: .timeOfDay,
                                 label: "ML area safety score: \(mlScore)/100",
                                 impact: mlScore - 50, provenance: .real))
        }

        var state = Self.state(forScore: score)

        // The one legitimate override: a genuine, already-happened emergency
        // event (not a predictive guess) always forces .emergency, regardless
        // of what the area score says.
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
