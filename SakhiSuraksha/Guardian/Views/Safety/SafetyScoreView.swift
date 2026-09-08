//
//  SafetyScoreView.swift
//  Guardian
//
//  The transparent, explainable safety confidence breakdown. Every reason is a
//  real SafetySignal produced by the SafetyEngine — no fabricated "AI" text.
//

import SwiftUI

struct SafetyScoreView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(spacing: GuardianTheme.cardSpacing) {
                gaugeCard
                if !app.confidence.negativeSignals.isEmpty {
                    reasonsCard(title: "What's lowering it",
                                signals: app.confidence.negativeSignals,
                                symbol: "arrow.down.right")
                }
                if !app.confidence.positiveSignals.isEmpty {
                    reasonsCard(title: "What's reassuring",
                                signals: app.confidence.positiveSignals,
                                symbol: "arrow.up.right")
                }
                engineNote
            }
            .padding()
        }
        .navigationTitle("Safety Score")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .guardianTrailing) {
                Button("Recompute") { app.recomputeSafety() }
            }
        }
    }

    private var gaugeCard: some View {
        GuardianCard {
            VStack(spacing: 14) {
                SafetyGauge(score: app.confidence.score, state: app.safetyState)
                SafetyStatusBadge(state: app.safetyState)
                Text("Updated \(app.confidence.updatedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func reasonsCard(title: String, signals: [SafetySignal], symbol: String) -> some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: title, systemImage: symbol)
                ForEach(signals) { signal in
                    SignalRow(signal: signal)
                    if signal.id != signals.last?.id { Divider() }
                }
            }
        }
    }

    private var engineNote: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("How this is calculated", systemImage: "cpu")
                    .font(.subheadline.weight(.semibold))
                Text("The score starts from a baseline and each signal adds or subtracts points based on your route, surroundings, time of day, connectivity and any watch/hardware events. The engine is modular — a trained model can replace it later behind the same interface.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
