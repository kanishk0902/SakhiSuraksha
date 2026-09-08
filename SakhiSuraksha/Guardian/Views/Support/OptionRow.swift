//
//  OptionRow.swift
//  Guardian
//
//  A calm, full-width list row used for option pickers (I Need Help, Period
//  Emergency, Safe Havens' type picker, the Get Help hub). Reads faster under
//  stress than a grid of boxes — one column, no shape-matching required.
//

import SwiftUI

struct OptionRow: View {
    let title: String
    let systemImage: String
    var subtitle: String? = nil
    var tint: Color = GuardianTheme.accent
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(tint.opacity(0.14))
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? tint : .secondary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A GuardianCard containing a vertical stack of OptionRows with dividers,
/// matching the app's list-inside-card idiom (see EmergencyContactsView,
/// WomenSupportView).
struct OptionRowList<Data: RandomAccessCollection, RowContent: View>: View where Data.Element: Identifiable {
    let data: Data
    @ViewBuilder var row: (Data.Element) -> RowContent

    var body: some View {
        GuardianCard {
            VStack(spacing: 0) {
                ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                    row(element)
                    if index != data.count - 1 { Divider() }
                }
            }
        }
    }
}
