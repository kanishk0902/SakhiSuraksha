//
//  GestureTriggerService.swift
//  GuardianWatch Watch App
//
//  Detects three sharp wrist flicks in quick succession using CoreMotion.
//  Foreground-only, matching the same honest limitation already documented
//  for Discreet SOS voice detection on the iPhone app: watchOS suspends
//  motion updates once the app leaves the active/foreground state, so this
//  is armed only while GuardianWatch is open and gesture detection is on —
//  not a true always-on background trigger. Detection is a simple, tunable
//  threshold on rotation-rate magnitude, not a claimed "fall detection" or
//  medical-grade gesture classifier.
//

import Foundation
import CoreMotion
import Observation

@Observable
final class GestureTriggerService {

    private(set) var isArmed = false
    /// 0...3 — how many flicks have been detected in the current window.
    private(set) var flickCount = 0
    /// True when real CoreMotion data drives detection. False in Simulator,
    /// where flicks can only be triggered via simulateFlick().
    var hasRealMotion: Bool { motionManager.isDeviceMotionAvailable }

    private let motionManager = CMMotionManager()
    private var onFlick: (() -> Void)?
    private var onTripleFlick: (() -> Void)?

    /// A flick is a rotation-rate spike above this magnitude (rad/s).
    private let flickThreshold: Double = 3.2
    /// Two flicks must land within this window of each other to count as
    /// the same "triple flick" gesture rather than three unrelated motions.
    private let flickWindow: TimeInterval = 2.0
    /// Minimum gap between two counted flicks, so one big motion isn't
    /// double-counted from a single gyroscope spike.
    private let refractoryPeriod: TimeInterval = 0.35

    private var lastFlickAt: Date?
    private var windowStartedAt: Date?
    private var resetTask: Task<Void, Never>?

    /// - Parameters:
    ///   - onFlick: called after every individual flick that counts toward
    ///     the gesture, so the UI can give immediate feedback (e.g. a tap).
    ///   - onTripleFlick: called once three flicks land within the window.
    func arm(onFlick: @escaping () -> Void, onTripleFlick: @escaping () -> Void) {
        guard !isArmed else { return }
        self.onFlick = onFlick
        self.onTripleFlick = onTripleFlick
        flickCount = 0
        windowStartedAt = nil
        lastFlickAt = nil

        // The Watch Simulator has no real gyroscope, so isDeviceMotionAvailable
        // is false there — arm anyway so simulateFlick() can drive the same
        // gesture pipeline for testing. On a real device this always starts
        // live motion updates.
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                self.processMotion(motion)
            }
        }
        isArmed = true
    }

    func disarm() {
        guard isArmed else { return }
        motionManager.stopDeviceMotionUpdates()
        resetTask?.cancel()
        isArmed = false
        flickCount = 0
        windowStartedAt = nil
        lastFlickAt = nil
        onFlick = nil
        onTripleFlick = nil
    }

    /// Temporarily stop processing motion without losing the "armed" intent —
    /// used while a countdown is in progress so a false-positive flick can't
    /// fire mid-countdown, then resumed (or left disarmed) once resolved.
    func pause() {
        motionManager.stopDeviceMotionUpdates()
    }

    func resume() {
        guard isArmed, !motionManager.isDeviceMotionActive else { return }
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.processMotion(motion)
        }
    }

    private func processMotion(_ motion: CMDeviceMotion) {
        let rate = motion.rotationRate
        let magnitude = (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot()
        guard magnitude >= flickThreshold else { return }
        registerFlick()
    }

    #if targetEnvironment(simulator)
    /// Simulator-only: the Watch Simulator has no real gyroscope, so this lets
    /// the UI drive the exact same gesture-counting pipeline a real flick
    /// would, for end-to-end testing without physical hardware. Compiled out
    /// of any real device build.
    func simulateFlick() {
        guard isArmed else { return }
        registerFlick()
    }
    #endif

    private func registerFlick() {
        let now = Date.now
        if let last = lastFlickAt, now.timeIntervalSince(last) < refractoryPeriod { return }
        lastFlickAt = now

        if let started = windowStartedAt, now.timeIntervalSince(started) > flickWindow {
            // Window expired — start a fresh count from this flick.
            flickCount = 0
            windowStartedAt = nil
        }
        if windowStartedAt == nil { windowStartedAt = now }

        flickCount += 1
        onFlick?()

        if flickCount >= 3 {
            let callback = onTripleFlick
            flickCount = 0
            windowStartedAt = nil
            callback?()
        } else {
            scheduleWindowReset()
        }
    }

    private func scheduleWindowReset() {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.flickWindow ?? 2.0))
            guard let self, !Task.isCancelled else { return }
            self.flickCount = 0
            self.windowStartedAt = nil
        }
    }
}
