//
//  GestureSOSSettingsView.swift
//  Guardian
//
//  Phone-side gesture SOS — the iPhone-only equivalent of GuardianWatch's
//  gesture trigger, no Apple Watch required. Once enabled, Guardian arms
//  motion detection automatically any time the app is open in the
//  foreground (see RootView's scenePhase handling) — iOS does not allow
//  unrestricted background motion access, so it always stops the moment
//  the app leaves the foreground and re-arms automatically on return.
//

import SwiftUI

struct GestureSOSSettingsView: View {
    @Environment(AppModel.self) private var app

    @State private var isEnabled = false
    @State private var countdownSeconds = 5

    var body: some View {
        Form {
            Section {
                Text("Flick your phone sharply three times in a row to silently start an SOS countdown you can cancel — no Apple Watch needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Enable Gesture SOS", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        app.gestureSOSAutoArm = newValue
                        if newValue {
                            app.armGestureSOS()
                        } else {
                            app.disarmGestureSOS()
                        }
                    }
                Stepper("Silent countdown: \(countdownSeconds)s", value: $countdownSeconds, in: 3...15)
                    .onChange(of: countdownSeconds) { _, newValue in
                        app.gestureSOSCountdownDuration = newValue
                    }
            }

            if !app.gestureTrigger.isAvailable {
                Section {
                    Label("Motion sensor unavailable on this device.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(GuardianTheme.caution)
                }
            }

            Section {
                Label(app.gestureTrigger.isArmed ? "Armed — listening for flicks" : "Not armed",
                      systemImage: app.gestureTrigger.isArmed ? "hand.wave.fill" : "hand.wave")
                    .foregroundStyle(app.gestureTrigger.isArmed ? GuardianTheme.safe : .secondary)
                if app.gestureTrigger.isArmed && app.gestureTrigger.flickCount > 0 {
                    Text("\(app.gestureTrigger.flickCount) of 3 flicks detected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Guardian arms automatically whenever it's open and Gesture SOS is enabled — no button to tap. It cannot detect gestures while the app is closed or in the background; that's an iOS platform limitation, not a bug.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Gesture SOS")
        .inlineNavigationTitle()
        .onAppear {
            isEnabled = app.gestureSOSAutoArm
            countdownSeconds = app.gestureSOSCountdownDuration
        }
    }
}
