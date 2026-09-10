//
//  GestureSOSCountdownSheet.swift
//  Guardian
//
//  Shown after three phone flicks are detected. Fast to dismiss if it was
//  accidental motion — mirrors DiscreetSOSCountdownSheet's design.
//

import SwiftUI

struct GestureSOSCountdownSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(GuardianTheme.emergency.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(GuardianTheme.emergency, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: app.gestureSOSCountdownSeconds)
                Text("\(app.gestureSOSCountdownSeconds)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
            }
            .frame(width: 140, height: 140)

            Text("Gesture detected. Sending an SOS alert unless you cancel.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                app.cancelGestureSOS()
            } label: {
                Text("Cancel")
                    .font(.headline)
                    .guardianCapsule(GuardianTheme.accent)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(32)
    }

    private var progress: CGFloat {
        CGFloat(app.gestureSOSCountdownSeconds % 10) / 10
    }
}
