//
//  EmergencyTimelineView.swift
//  Guardian
//
//  A flat, chronological log of one emergency's SOS + Community Guardian
//  events — written by AppModel and CommunityGuardianService via a single
//  path (CommunityGuardianService.logExternalEvent) so this always reflects
//  what actually happened, in order.
//

import SwiftUI
import SwiftData

struct EmergencyTimelineView: View {
    let emergencyID: UUID
    @Environment(\.dismiss) private var dismiss
    @Query private var allEvents: [EmergencyTimelineEvent]

    private var events: [EmergencyTimelineEvent] {
        allEvents
            .filter { $0.emergencyID == emergencyID }
            .sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            List {
                if events.isEmpty {
                    Text("No timeline events yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(events, id: \.eventID) { event in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.label).font(.subheadline)
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ProvenanceBadge(provenance: event.provenance)
                    }
                }
            }
            .navigationTitle("Emergency Timeline")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .guardianLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
