//
//  WomenSupportView.swift
//  Guardian
//
//  Official government helplines, One Stop Centres, and verified NGOs — all
//  sourced from SupportResourcesService. Never invents an NGO or marks one
//  verified without the service itself asserting isVerified == true.
//

import SwiftUI

struct WomenSupportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GuardianTheme.cardSpacing) {
                    helplinesCard
                    oneStopCentreCard
                    ngoCard
                }
                .padding()
            }
            .navigationTitle("Women's Support")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var helplinesCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Helplines", systemImage: "phone.fill")
                ForEach(app.support.helplines) { resource in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(resource.name).font(.subheadline.weight(.semibold))
                            Text(resource.description).font(.caption).foregroundStyle(.secondary)
                            if let hours = resource.operatingHours {
                                Text(hours).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let phone = resource.phone {
                            Button { app.support.call(resource) } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "phone.fill")
                                    Text(phone).font(.caption2)
                                }
                                .foregroundStyle(GuardianTheme.safe)
                            }
                        }
                    }
                    if resource.id != app.support.helplines.last?.id { Divider() }
                }
            }
        }
    }

    private var oneStopCentreCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 8) {
                GuardianSectionHeader(title: "One Stop Centres", systemImage: "building.2.fill")
                Text(app.support.oneStopCentreNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ngoCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 10) {
                GuardianSectionHeader(title: "Verified NGOs", systemImage: "heart.fill")
                if app.support.verifiedNGOs.isEmpty {
                    Text("Verified local organisations will appear here once our admin system has confirmed them.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(app.support.verifiedNGOs) { ngo in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(ngo.name).font(.subheadline.weight(.semibold))
                                Label("Verified", systemImage: "checkmark.seal.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(GuardianTheme.safe)
                            }
                            Text(ngo.description).font(.caption).foregroundStyle(.secondary)
                        }
                        if ngo.id != app.support.verifiedNGOs.last?.id { Divider() }
                    }
                }
            }
        }
    }
}
