//
//  TurnBanner.swift
//  Guardian
//
//  First-person, turn-by-turn instruction banner for an active journey.
//  Built from real MKRoute.Step data (RoutingService/RouteResult.steps) —
//  MapKit gives free-text instructions ("Turn left onto MG Road") rather
//  than a structured maneuver type, so the arrow/icon is inferred from that
//  text via simple keyword matching. If MapKit's phrasing doesn't match any
//  known pattern, a neutral "continue" arrow is shown rather than guessing
//  wrong — this is a best-effort translation of real routing data, not a
//  claim of a dedicated maneuver-classification model.
//

import SwiftUI

enum TurnDirection {
    case left, right, slightLeft, slightRight, uTurn, straight, arrive

    var symbol: String {
        switch self {
        case .left:        return "arrow.turn.up.left"
        case .right:        return "arrow.turn.up.right"
        case .slightLeft:  return "arrow.up.left"
        case .slightRight: return "arrow.up.right"
        case .uTurn:       return "arrow.uturn.up"
        case .straight:    return "arrow.up"
        case .arrive:      return "flag.checkered.circle.fill"
        }
    }

    static func infer(from instructions: String) -> TurnDirection {
        let text = instructions.lowercased()
        if text.contains("arrive") || text.contains("destination") { return .arrive }
        if text.contains("u-turn") || text.contains("u turn") { return .uTurn }
        if text.contains("slight left") { return .slightLeft }
        if text.contains("slight right") { return .slightRight }
        if text.contains("left") { return .left }
        if text.contains("right") { return .right }
        return .straight
    }
}

struct TurnBanner: View {
    let step: RouteStep
    let distanceMeters: Double?

    private var direction: TurnDirection { .infer(from: step.instructions) }

    private var distanceText: String {
        guard let distanceMeters else { return "" }
        return distanceMeters < 1000 ? "in \(Int(distanceMeters)) m" : String(format: "in %.1f km", distanceMeters / 1000)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: direction.symbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(GuardianTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(step.instructions)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if !distanceText.isEmpty {
                    Text(distanceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
