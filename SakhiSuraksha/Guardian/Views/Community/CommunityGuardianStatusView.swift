//
//  CommunityGuardianStatusView.swift
//  Guardian
//
//  Requester-side view of an in-progress Community Guardian search — reached
//  from SOSView's "View Details" button. Regardless of what's shown here, the
//  existing SOS/112/trusted-contacts flow keeps running unaffected.
//

import SwiftUI
import MapKit

struct CommunityGuardianStatusView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var showTimeline = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GuardianTheme.cardSpacing) {
                    stateCard
                    if !app.guardianService.activeRequests.isEmpty {
                        requestsCard
                    }
                    safeHavenCard
                    Button("View Emergency Timeline") { showTimeline = true }
                        .font(.footnote.weight(.semibold))
                }
                .padding()
            }
            .navigationTitle("Community Guardian")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .guardianLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showTimeline) {
                if let emergencyID = app.emergency.currentPacket?.packetID {
                    EmergencyTimelineView(emergencyID: emergencyID)
                }
            }
        }
    }

    private var stateCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 10) {
                GuardianSectionHeader(title: "Status", systemImage: "person.2.wave.2.fill")
                Text(app.guardianService.flowState.title.isEmpty
                     ? "Community Guardian is not active for this emergency."
                     : app.guardianService.flowState.title)
                    .font(.subheadline)
                if app.guardianService.flowState == .searching {
                    Text("Searching within \(Int(app.guardianService.currentSearchRadius))m")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if app.guardianService.flowState == .failed {
                    Text("Your emergency call, trusted contacts, and location sharing remain active regardless.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var requestsCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Guardians Notified", systemImage: "person.2.fill")
                ForEach(app.guardianService.activeRequests, id: \.requestID) { request in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(request.status.title).font(.subheadline.weight(.semibold))
                            Text("\(Int(request.approximateDistanceMeters)) m away")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ProvenanceBadge(provenance: request.provenance)
                    }
                    if request.requestID != app.guardianService.activeRequests.last?.requestID {
                        Divider()
                    }
                }
            }
        }
    }

    private var safeHavenCard: some View {
        let coordinate = app.location.currentLocation?.coordinate ?? LocationService.fallbackCoordinate
        let nearest = app.support.nearestNGOs(to: coordinate, limit: 1).first
        return GuardianCard {
            VStack(alignment: .leading, spacing: 10) {
                GuardianSectionHeader(title: "Nearest Verified Safe Haven", systemImage: "shield.lefthalf.filled")
                if let nearest {
                    Text(nearest.name).font(.subheadline.weight(.semibold))
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: nearest.coordinate))
                        item.name = nearest.name
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                    } label: {
                        Label("Navigate to Safe Haven", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("No verified Safe Haven found nearby yet.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}
