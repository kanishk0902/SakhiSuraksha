//
//  CheckInSheet.swift
//  Guardian
//
//  The intelligent safety check-in. A non-response never assumes danger — it
//  only gently raises the caution state per the RiskEngine rules.
//

import SwiftUI

struct CheckInSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            Image(systemName: "hand.wave.fill")
                .font(.system(size: 44))
                .foregroundStyle(GuardianTheme.caution)
                .symbolEffect(.pulse)

            Text(app.checkInPrompt)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("If you don't respond, Guardian will gently raise your caution level — it won't assume you're in danger.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                PrimaryActionButton(title: "I'm Safe", systemImage: "checkmark.circle.fill",
                                    color: GuardianTheme.safe) {
                    app.respondSafe()
                }
                PrimaryActionButton(title: "I'm Taking Another Route",
                                    systemImage: "arrow.triangle.branch",
                                    color: GuardianTheme.accent) {
                    app.respondTakingAnotherRoute()
                }
                PrimaryActionButton(title: "I Need Help", systemImage: "sos",
                                    color: GuardianTheme.emergency) {
                    app.respondNeedHelp()
                }
            }
            Spacer(minLength: 8)
        }
        .padding()
    }
}
