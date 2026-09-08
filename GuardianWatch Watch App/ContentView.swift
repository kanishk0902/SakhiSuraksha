//
//  ContentView.swift
//  GuardianWatch Watch App
//
//  Arm gesture detection, then either a triple wrist-flick or the manual SOS
//  button starts a short cancellable countdown before sending an SOS event to
//  the phone. The phone's EmergencyService does the real work (packet
//  creation, contact notification, timeline) — the Watch app is a trigger
//  surface only, matching AppModel.ingest(watchEvent:) on iOS.
//

import SwiftUI
import WatchKit

struct ContentView: View {
    @Environment(PhoneConnectivityService.self) private var connectivity
    @Environment(GestureTriggerService.self) private var gesture
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("guardian.watch.autoArm") private var autoArm = true

    @State private var sosState: SOSState = .idle
    @State private var countdownSeconds = 0
    @State private var countdownTask: Task<Void, Never>?

    private let countdownDuration = 5

    enum SOSState { case idle, countdown, sent }

    var body: some View {
        Group {
            switch sosState {
            case .idle:      idleView
            case .countdown: countdownView
            case .sent:      sentView
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if autoArm { armGesture() }
            } else {
                gesture.disarm()
            }
        }
        .onAppear {
            if autoArm { armGesture() }
        }
    }

    // MARK: Idle

    private var idleView: some View {
        ScrollView {
            VStack(spacing: 12) {
                connectionChip

                armToggleCard

                sosButton

                #if targetEnvironment(simulator)
                simulateFlickButton
                #endif

                Text("Only active while Guardian is open on your wrist.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
    }

    private var connectionChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connectivity.isReachable ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(connectivity.isReachable ? "iPhone Connected" : "iPhone Not Reachable")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private var armToggleCard: some View {
        Button {
            toggleArmed()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(gesture.isArmed ? Color.green.opacity(0.16) : Color.gray.opacity(0.18))
                        .frame(width: 64, height: 64)
                    if gesture.isArmed && gesture.flickCount > 0 {
                        Circle()
                            .trim(from: 0, to: CGFloat(gesture.flickCount) / 3)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 64, height: 64)
                            .animation(.easeOut(duration: 0.2), value: gesture.flickCount)
                    }
                    Image(systemName: gesture.isArmed ? "hand.wave.fill" : "hand.wave")
                        .font(.system(size: 24))
                        .foregroundStyle(gesture.isArmed ? .green : .secondary)
                }

                Text(armStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(gesture.isArmed ? .primary : .secondary)

                Text(gesture.isArmed
                     ? "Flick your wrist sharply 3 times for SOS"
                     : "Tap to arm gesture detection")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if !gesture.hasRealMotion {
                    Text("Simulator Mode — use Simulate Flick below")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var armStatusText: String {
        guard gesture.isArmed else { return "Gesture Off" }
        return gesture.flickCount == 0 ? "Armed" : "\(gesture.flickCount) of 3 flicks"
    }

    #if targetEnvironment(simulator)
    /// Debug-only control, compiled out of real device builds. Lets you drive
    /// the exact same gesture pipeline as a real flick would, since the Watch
    /// Simulator has no gyroscope to generate real motion data.
    private var simulateFlickButton: some View {
        Button {
            gesture.simulateFlick()
            WKInterfaceDevice.current().play(.click)
        } label: {
            Label("Simulate Flick", systemImage: "hand.point.up.braille.fill")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.orange)
        .disabled(!gesture.isArmed)
    }
    #endif

    private var sosButton: some View {
        Button(role: .destructive) {
            beginCountdown()
        } label: {
            Label("SOS", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }

    // MARK: Countdown

    private var countdownView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.25), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(countdownSeconds) / CGFloat(countdownDuration))
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: countdownSeconds)
                Text("\(countdownSeconds)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            .frame(width: 96, height: 96)

            Text("Sending SOS unless cancelled")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                cancelCountdown()
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.primary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Sent

    private var sentView: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text("SOS Sent")
                .font(.headline)
            Text(connectivity.isReachable
                 ? "Your iPhone will notify your trusted contacts."
                 : "Will send once your iPhone is reachable.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") {
                sosState = .idle
                if autoArm { armGesture() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Actions

    private func toggleArmed() {
        if gesture.isArmed {
            gesture.disarm()
            autoArm = false
        } else {
            armGesture()
            autoArm = true
        }
        WKInterfaceDevice.current().play(.click)
    }

    private func armGesture() {
        guard sosState == .idle else { return }
        gesture.arm(onFlick: {
            WKInterfaceDevice.current().play(.click)
        }, onTripleFlick: {
            beginCountdown()
        })
    }

    private func beginCountdown() {
        guard sosState == .idle else { return }
        sosState = .countdown
        countdownSeconds = countdownDuration
        gesture.pause() // don't let more flicks fire while we're already counting down
        WKInterfaceDevice.current().play(.notification)

        countdownTask?.cancel()
        countdownTask = Task {
            while countdownSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                countdownSeconds -= 1
                if countdownSeconds <= 2 { WKInterfaceDevice.current().play(.directionUp) }
            }
            guard !Task.isCancelled else { return }
            sendSOS()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        sosState = .idle
        WKInterfaceDevice.current().play(.click)
        if gesture.isArmed { gesture.resume() }
    }

    private func sendSOS() {
        connectivity.send(.sos)
        WKInterfaceDevice.current().play(.success)
        gesture.disarm()
        sosState = .sent
    }
}

#Preview {
    ContentView()
        .environment(PhoneConnectivityService())
        .environment(GestureTriggerService())
}
