//
//  NavigationVoiceService.swift
//  Guardian
//
//  Real spoken turn-by-turn narration for active navigation, using
//  AVSpeechSynthesizer. Screen-scoped (owned by ActiveNavigationView, not
//  AppModel) since no other screen narrates. Dedupes by step index so the
//  same instruction is never announced twice.
//
//  Known limitation: AVSpeechSynthesizer does not speak while the app is
//  suspended/backgrounded, and this project configures no background-audio
//  session. Voice guidance only works while the app is in the foreground —
//  journey monitoring itself (deviation/SOS) is unaffected and already works
//  backgrounded via LocationService.setBackgroundTracking.
//

import Foundation
import AVFoundation
import Observation

@Observable
final class NavigationVoiceService: NSObject, AVSpeechSynthesizerDelegate {

    // nonisolated(unsafe): AVSpeechSynthesizer isn't Sendable, but this
    // class is MainActor-isolated by the project's default actor isolation,
    // so it's only ever touched from one actor — same pattern MeshService
    // uses for its own non-Sendable MultipeerConnectivity objects.
    @ObservationIgnored nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var lastAnnouncedStepIndex: Int?

    var isMuted: Bool {
        didSet { UserDefaults.standard.set(isMuted, forKey: Self.mutedKey) }
    }

    private static let mutedKey = "guardian.navigation.voiceMuted"

    override init() {
        isMuted = UserDefaults.standard.bool(forKey: Self.mutedKey)
        super.init()
        synthesizer.delegate = self
    }

    /// Announces the current step once per step-index change. Silent no-op
    /// when muted, when there's nothing new to say, or when data is missing.
    func announceIfNeeded(step: RouteStep?, stepIndex: Int?, distanceMeters: Double?) {
        guard !isMuted, let step, let stepIndex, stepIndex != lastAnnouncedStepIndex else { return }
        lastAnnouncedStepIndex = stepIndex

        let direction = TurnDirection.infer(from: step.instructions)
        let distancePhrase: String
        if let distanceMeters {
            distancePhrase = distanceMeters < 1000
                ? "In \(Int(distanceMeters)) meters, "
                : String(format: "In %.1f kilometers, ", distanceMeters / 1000)
        } else {
            distancePhrase = ""
        }
        let text = distancePhrase + Self.phrase(for: direction, fallback: step.instructions)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        synthesizer.speak(utterance)
    }

    /// Call when a journey/navigation session ends or restarts, so a fresh
    /// session can announce its first step (dedup is per-session, not global).
    func reset() {
        lastAnnouncedStepIndex = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Real MapKit instructions have no structured maneuver type (see
    /// TurnDirection's own doc comment) — only .straight falls back to the
    /// raw instruction text since there's no generic-enough spoken phrase for
    /// "continue" that fits every possible straight-ahead instruction.
    private static func phrase(for direction: TurnDirection, fallback: String) -> String {
        switch direction {
        case .left:        return "turn left."
        case .right:       return "turn right."
        case .slightLeft:  return "bear left."
        case .slightRight: return "bear right."
        case .uTurn:       return "make a U-turn."
        case .arrive:      return "you have arrived at your destination."
        case .straight:    return fallback
        }
    }
}
