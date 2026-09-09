//
//  GuardianDashboardView.swift
//  Guardian
//
//  This device acting as a Community Guardian: an incoming request shows only
//  approximate distance + emergency category (never name/phone/exact
//  location) until accepted, then a safety-confirmation step, then an active
//  assistance card. Full details are gated behind acceptance by design — see
//  CommunityGuardianService's privacy notes.
//

import SwiftUI
import MapKit

struct GuardianDashboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var showSafetyConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GuardianTheme.cardSpacing) {
                    statusCard
                    if let request = app.guardianService.incomingRequest {
                        if request.status == .accepted {
                            activeAssistanceCard(request)
                        } else {
                            incomingRequestCard(request)
                        }
                    } else {
                        GuardianCard {
                            Text("No active request right now. When you're available and a nearby emergency needs assistance, a request will appear here.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Guardian Dashboard")
            .inlineNavigationTitle()
        }
        .sheet(isPresented: $showSafetyConfirmation) {
            GuardianSafetyConfirmationView {
                app.guardianService.acceptIncomingRequest()
            }
        }
    }

    private var statusCard: some View {
        GuardianCard {
            HStack {
                Label(app.guardianService.localAvailability.title,
                      systemImage: "person.2.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(app.guardianService.localAvailability.color)
                Spacer()
                ProvenanceBadge(provenance: .real)
            }
        }
    }

    private func incomingRequestCard(_ request: CommunityGuardianRequest) -> some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 14) {
                GuardianSectionHeader(title: "Community Guardian Request", systemImage: "bell.badge.fill")
                Text("Emergency assistance is needed nearby.")
                    .font(.subheadline)
                HStack {
                    Label("Approximate distance", systemImage: "location.fill")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(distanceText(request.approximateDistanceMeters))
                        .font(.subheadline.weight(.semibold))
                }
                HStack {
                    Text("Immediate assistance requested")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    ProvenanceBadge(provenance: request.provenance)
                }
                Text("Can you safely assist?")
                    .font(.footnote.weight(.semibold))

                HStack(spacing: 12) {
                    SecondaryActionButton(title: "Decline", systemImage: "xmark.circle",
                                          tint: .secondary) {
                        app.guardianService.declineIncomingRequest()
                    }
                    SecondaryActionButton(title: "Accept", systemImage: "checkmark.circle.fill",
                                          tint: GuardianTheme.safe) {
                        showSafetyConfirmation = true
                    }
                }
            }
        }
    }

    private func activeAssistanceCard(_ request: CommunityGuardianRequest) -> some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 14) {
                GuardianSectionHeader(title: "Responding", systemImage: "figure.walk")
                Text("Professional emergency services remain active for this emergency. You are providing an additional layer of nearby assistance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let coordinate = app.guardianService.incomingEmergencyCoordinate {
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                        item.name = "Person requesting assistance"
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                    } label: {
                        Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SecondaryActionButton(title: "Call 112", systemImage: "phone.fill",
                                          tint: GuardianTheme.emergency) {
                        if let url = URL(string: "tel://112") { openURL(url) }
                    }
                    SecondaryActionButton(title: "Unable to Continue", systemImage: "hand.raised.slash",
                                          tint: GuardianTheme.caution) {
                        app.guardianService.cannotContinue()
                    }
                }
                PrimaryActionButton(title: "Assistance Completed", systemImage: "checkmark.seal.fill",
                                    color: GuardianTheme.safe) {
                    app.guardianService.completeAssistance()
                }
            }
        }
    }

    private func distanceText(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters)) m" : String(format: "%.1f km", meters / 1000)
    }
}
