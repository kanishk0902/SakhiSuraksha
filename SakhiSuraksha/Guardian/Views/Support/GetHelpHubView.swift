//
//  GetHelpHubView.swift
//  Guardian
//
//  Single entry point for every non-instant-SOS support feature. Keeps Home
//  short by pushing the six destinations here as one calm list instead of a
//  grid of tiles competing with Home's other content.
//

import SwiftUI

struct GetHelpHubView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private enum Destination: Identifiable {
        case medical, period, general, safeHavens, womenSupport, report
        var id: Self { self }
    }
    @State private var destination: Destination?

    private struct Item: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color
        let destination: Destination
    }

    private let items: [Item] = [
        Item(title: "Medical SOS", subtitle: "Injury, fainting, pregnancy & more",
             symbol: "cross.case.fill", tint: GuardianTheme.emergency, destination: .medical),
        Item(title: "Period Emergency", subtitle: "Pads, pharmacy, washroom, assistance",
             symbol: "drop.fill", tint: .pink, destination: .period),
        Item(title: "I Need Help", subtitle: "Everyday needs — not necessarily an emergency",
             symbol: "hand.raised.fill", tint: GuardianTheme.accent, destination: .general),
        Item(title: "Safe Havens", subtitle: "Nearby places to wait or get assistance",
             symbol: "storefront.fill", tint: GuardianTheme.safe, destination: .safeHavens),
        Item(title: "Women's Support", subtitle: "Helplines, One Stop Centres, verified NGOs",
             symbol: "heart.fill", tint: .pink, destination: .womenSupport),
        Item(title: "Safety Reports", subtitle: "View nearby reports, or report a concern",
             symbol: "flag.fill", tint: GuardianTheme.caution, destination: .report),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GuardianTheme.cardSpacing) {
                    GuardianCard {
                        Label("None of these are automatically an emergency call — pick what fits your situation.",
                              systemImage: "info.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    OptionRowList(data: items) { item in
                        OptionRow(title: item.title, systemImage: item.symbol,
                                 subtitle: item.subtitle, tint: item.tint) {
                            destination = item.destination
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Get Help")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $destination) { destination in
                switch destination {
                case .medical:      MedicalSOSView()
                case .period:       PeriodEmergencyView()
                case .general:      INeedHelpView()
                case .safeHavens:   SafeHavensView()
                case .womenSupport: WomenSupportView()
                case .report:       SafetyReportsView()
                }
            }
        }
    }
}
