//
//  Components.swift
//  Guardian
//
//  Reusable presentation components shared across the feature screens.
//

import SwiftUI
import CoreLocation

// MARK: - Safety confidence ring

struct SafetyGauge: View {
    let score: Int
    let state: SafetyState
    var size: CGFloat = 190

    private var fraction: CGFloat { CGFloat(max(0, min(100, score))) / 100 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(state.color,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: fraction)
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("of 100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Safety confidence \(score) of 100, status \(state.title)")
    }
}

// MARK: - Status header

struct SafetyStatusBadge: View {
    let state: SafetyState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.symbol)
            Text(state.title)
                .font(.subheadline.weight(.bold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(state.color.opacity(0.16))
        .foregroundStyle(state.color)
        .clipShape(Capsule())
    }
}

// MARK: - Connectivity chip

struct ConnectivityChip: View {
    let state: ConnectivityState
    var forced: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state.symbol)
            Text(state.title)
                .font(.caption.weight(.semibold))
            if forced {
                Image(systemName: "wrench.adjustable.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(state.color.opacity(0.16))
        .foregroundStyle(state.color)
        .clipShape(Capsule())
        .accessibilityLabel("Connectivity \(state.title)\(forced ? ", simulated" : "")")
    }
}

// MARK: - Info tile (small metric card)

struct InfoTile: View {
    let title: String
    let value: String
    var systemImage: String
    var tint: Color = GuardianTheme.accent

    var body: some View {
        GuardianCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .font(.title3)
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Large primary action button

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    var color: Color = GuardianTheme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.headline)
            }
            .guardianCapsule(color)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - Secondary action button (outlined)

struct SecondaryActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = GuardianTheme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Safe place row

struct SafePlaceRow: View {
    let place: SafePlace
    var distance: CLLocationDistance?

    private var distanceText: String? {
        guard let distance else { return nil }
        return distance < 1000 ? "\(Int(distance)) m"
            : String(format: "%.1f km", distance / 1000)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(place.type.tint.opacity(0.18))
                Image(systemName: place.type.symbol)
                    .foregroundStyle(place.type.tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(place.type.title)
                    if let distanceText {
                        Text("· \(distanceText)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(place.safetyScore)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GuardianTheme.safe)
                ProvenanceBadge(provenance: place.provenance)
            }
        }
    }
}

// MARK: - Signal row (why the score changed)

struct SignalRow: View {
    let signal: SafetySignal

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: signal.symbol)
                .frame(width: 24)
                .foregroundStyle(signal.isPositive ? GuardianTheme.safe : GuardianTheme.alert)
            Text(signal.label)
                .font(.subheadline)
            Spacer()
            Text(signal.impact >= 0 ? "+\(signal.impact)" : "\(signal.impact)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(signal.isPositive ? GuardianTheme.safe : GuardianTheme.alert)
        }
    }
}

// MARK: - Availability row (offline screen)

struct AvailabilityRow: View {
    let title: String
    let available: Bool

    var body: some View {
        HStack {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? GuardianTheme.safe : .secondary)
            Text(title)
            Spacer()
            Text(available ? "Available" : "Needs network")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(title), \(available ? "available offline" : "needs network")")
    }
}
