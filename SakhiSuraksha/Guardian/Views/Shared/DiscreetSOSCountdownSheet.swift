//
//  DiscreetSOSCountdownSheet.swift
//  Guardian
//
//  A silent, fast-to-dismiss confirmation shown after the discreet phrase is
//  detected. No sound, minimal text — this exists to be cancelled quickly and
//  wordlessly if it was a false trigger.
//

import SwiftUI

struct DiscreetSOSCountdownSheet: View {
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
                    .animation(.linear(duration: 1), value: app.discreetSOSCountdownSeconds)
                Text("\(app.discreetSOSCountdownSeconds)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
            }
            .frame(width: 140, height: 140)

            Text("Sending a silent alert unless you cancel.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                app.cancelDiscreetSOS()
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
        // Approximate: unknown total, so just show a steady countdown ring.
        CGFloat(app.discreetSOSCountdownSeconds % 10) / 10
    }
}
