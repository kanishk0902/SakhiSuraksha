//
//  Theme.swift
//  Guardian
//
//  Central visual language for the Guardian safety system.
//  Dark-mode-first, restrained color, large readable typography.
//

import SwiftUI

enum GuardianTheme {

    // MARK: Brand palette

    /// Primary brand accent — a calm, trustworthy indigo.
    static let accent = Color(red: 0.42, green: 0.47, blue: 0.98)

    /// Secondary accent used for "safe" affirmations.
    static let safe = Color(red: 0.20, green: 0.78, blue: 0.55)

    static let caution = Color(red: 0.98, green: 0.72, blue: 0.24)
    static let alert = Color(red: 0.98, green: 0.48, blue: 0.24)
    static let emergency = Color(red: 0.95, green: 0.26, blue: 0.32)

    // MARK: Surfaces

    /// Rounded card background that adapts to color scheme.
    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.11)
            : Color(white: 1.0)
    }

    static func groupedBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black
            : Color(white: 0.95)
    }

    // MARK: Metrics

    static let cornerRadius: CGFloat = 20
    static let cardPadding: CGFloat = 18
    static let cardSpacing: CGFloat = 14
}

// MARK: - Reusable card container

/// A rounded, subtly shadowed surface used throughout the app.
struct GuardianCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = GuardianTheme.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GuardianTheme.card(scheme))
            .clipShape(RoundedRectangle(cornerRadius: GuardianTheme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.08),
                    radius: 12, x: 0, y: 6)
    }
}

// MARK: - Section header

struct GuardianSectionHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(GuardianTheme.accent)
            }
            Text(title)
                .font(.headline)
            Spacer()
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Provenance badge (REAL / SIMULATED / CACHED / OFFLINE / FUTURE)

struct ProvenanceBadge: View {
    let provenance: DataProvenance

    var body: some View {
        Text(provenance.label)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(provenance.tint.opacity(0.18))
            .foregroundStyle(provenance.tint)
            .clipShape(Capsule())
            .accessibilityLabel("Data source: \(provenance.label)")
    }
}

// MARK: - Pressable button style with haptic-friendly scale

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    /// Convenience for the frequent "full-width rounded prominent action" look.
    func guardianCapsule(_ color: Color) -> some View {
        self
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}
