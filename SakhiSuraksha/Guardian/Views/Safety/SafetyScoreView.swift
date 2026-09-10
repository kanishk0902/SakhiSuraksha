//
//  SafetyScoreView.swift
//  Guardian
//
//  The transparent, explainable safety confidence breakdown. Every reason is a
//  real SafetySignal produced by the SafetyEngine — no fabricated "AI" text.
//

import SwiftUI
import CoreLocation

struct SafetyScoreView: View {
    @Environment(AppModel.self) private var app
    @State private var showLimitations = false

    /// Shares AppModel's instance (not a local one) so this view reflects
    /// the same ML score that's already feeding the main safety gauge above
    /// — no duplicate network call, and the two numbers can never disagree.
    private var routing: SafeRoutingService { app.safeRouting }

    var body: some View {
        ScrollView {
            VStack(spacing: GuardianTheme.cardSpacing) {
                gaugeCard
                mlLocationSafetyCard
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
        .task { await fetchLocationSafety() }
    }

    // MARK: ML location safety (Jaipur model)

    private func fetchLocationSafety() async {
        let coord = app.location.currentLocation?.coordinate ?? LocationService.fallbackCoordinate
        await routing.fetchLocationSafety(at: coord)
        // Opening this screen shouldn't have to wait for AppModel's own
        // ~2-minute background refresh cycle to reflect a fresh score.
        app.recomputeSafety()
    }

    private var mlLocationSafetyCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    GuardianSectionHeader(title: "ML Area Safety Score", systemImage: "shield.checkerboard")
                    Spacer()
                    BetaBadge()
                }

                if routing.isLoadingLocationSafety {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Scoring your area…").font(.footnote).foregroundStyle(.secondary)
                    }
                } else if let error = routing.locationSafetyError {
                    Text(mlErrorText(error))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Try Again") { Task { await fetchLocationSafety() } }
                        .font(.footnote.weight(.semibold))
                } else if let safety = routing.locationSafety {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        // Real decimal score as returned by the model — not
                        // rounded to a falsely-precise-looking integer.
                        Text(String(format: "%.1f", safety.safetyScore))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(safety.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(safety.tier.title).font(.subheadline.weight(.semibold))
                                .foregroundStyle(safety.color)
                            Text("out of 100 — this street area").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            showLimitations = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .disabled((safety.disclosedLimitations ?? []).isEmpty)
                    }
                    if let factors = safety.factors, !factors.isEmpty {
                        Divider()
                        Text("What went into this")
                            .font(.caption.weight(.semibold))
                        ForEach(factors) { factor in
                            factorRow(factor)
                        }
                    }

                    Text("Predicted by a model trained on ~368k Jaipur street segments. The score is a percentile rank: \(String(format: "%.0f", safety.safetyScore)) means safer than about \(String(format: "%.0f", safety.safetyScore))% of Jaipur's mapped streets — it is a comparison against this city, not an absolute rating.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Unavailable.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showLimitations) {
            limitationsSheet(routing.locationSafety?.disclosedLimitations ?? [])
        }
    }

    /// One factor row: the real measurement, plus a bar for the model's own
    /// 0-1 risk input. The citywide crime factor deliberately has no bar —
    /// it's identical everywhere in Jaipur, so drawing it as if it varied
    /// per-street would misrepresent what it is.
    private func factorRow(_ factor: SafetyFactor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(factor.label)
                    .font(.caption.weight(.medium))
                Spacer()
                if let score = factor.contributionScore {
                    Text("\(score)/100")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(factorColor(score))
                } else if factor.citywide == true {
                    Text("citywide")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let score = factor.contributionScore {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(factorColor(score))
                            .frame(width: geo.size.width * CGFloat(score) / 100)
                    }
                }
                .frame(height: 4)
            }
            Text(factor.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func factorColor(_ score: Int) -> Color {
        if score >= 70 { return GuardianTheme.safe }
        if score >= 35 { return GuardianTheme.caution }
        return GuardianTheme.emergency
    }

    private func limitationsSheet(_ limitations: [String]) -> some View {
        NavigationStack {
            List(limitations, id: \.self) { item in
                Text(item).font(.subheadline)
            }
            .navigationTitle("Model Limitations")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showLimitations = false }
                }
            }
        }
    }

    private func mlErrorText(_ error: SafeRoutingError) -> String {
        switch error {
        case .outOfCoverage:
            return "This model only covers the Jaipur area — your current location is outside its coverage, so no score is available here."
        default:
            return error.errorDescription ?? "The ML safety score is unavailable right now."
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
                Text("This score is the ML model's area safety score for where you are — nothing else is mixed in. Route deviation, connectivity and time of day used to add or subtract invented points; they no longer affect the number, because those adjustments were guesses rather than measurements. An active SOS still overrides the status regardless of the score.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
