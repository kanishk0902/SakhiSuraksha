//
//  LocationSharingView.swift
//  Guardian
//
//  Shares your real GPS coordinates via the iOS share sheet (Messages, WhatsApp,
//  email, etc.) or opens a pre-filled SMS to your emergency contacts.
//

import SwiftUI
import SwiftData
import CoreLocation
import MessageUI

struct LocationSharingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Query(sort: \EmergencyContact.name) private var contacts: [EmergencyContact]

    @State private var showShareSheet = false
    @State private var shareText = ""
    @State private var lastSharedAt: Date?

    private var coordinate: CLLocationCoordinate2D? {
        app.location.currentLocation?.coordinate
    }

    private var locationString: String {
        guard let c = coordinate else { return "Location unavailable" }
        return String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }

    private var mapsLink: String {
        guard let c = coordinate else { return "" }
        return "https://maps.apple.com/?q=\(c.latitude),\(c.longitude)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GuardianTheme.cardSpacing) {
                locationCard
                if !contacts.isEmpty { contactsCard }
                shareCard
            }
            .padding()
        }
        .navigationTitle("Share Location")
        .inlineNavigationTitle()
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
    }

    // MARK: Current location

    private var locationCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Your Location", systemImage: "location.fill")
                        .font(.headline)
                    Spacer()
                    ConnectivityChip(state: app.connectivity.state,
                                     forced: app.connectivity.isForced)
                }
                if coordinate != nil {
                    Text(locationString)
                        .font(.subheadline.monospacedDigit().weight(.medium))
                    Text(mapsLink)
                        .font(.caption)
                        .foregroundStyle(GuardianTheme.accent)
                    if let last = lastSharedAt {
                        Text("Last shared \(last.formatted(date: .omitted, time: .standard))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Label("Waiting for GPS…", systemImage: "location.slash")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Quick SMS to contacts

    private var contactsCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Send to Emergency Contact",
                                      systemImage: "message.fill")
                ForEach(contacts) { contact in
                    Button {
                        sendSMS(to: contact)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(GuardianTheme.accent.opacity(0.18))
                                Text(contact.initials).font(.caption.weight(.bold))
                                    .foregroundStyle(GuardianTheme.accent)
                            }
                            .frame(width: 38, height: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name).font(.subheadline.weight(.semibold))
                                Text(contact.phone).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "message.fill")
                                .foregroundStyle(GuardianTheme.safe)
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(PressableStyle())
                    if contact.id != contacts.last?.id { Divider() }
                }
            }
        }
    }

    // MARK: Share sheet

    private var shareCard: some View {
        VStack(spacing: 12) {
            PrimaryActionButton(
                title: "Share via…",
                systemImage: "square.and.arrow.up",
                color: coordinate != nil ? GuardianTheme.accent : .secondary
            ) {
                guard coordinate != nil else { return }
                shareText = buildMessage()
                showShareSheet = true
                lastSharedAt = .now
            }
            .disabled(coordinate == nil)
            .opacity(coordinate == nil ? 0.6 : 1)

            Text("Opens the iOS share sheet — send via Messages, WhatsApp, email or any app.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Helpers

    private func buildMessage() -> String {
        var msg = "📍 My current location: \(mapsLink)"
        if let journey = app.journey.active {
            msg += "\nI'm on my way to \(journey.destinationName)."
        }
        msg += "\nSent from Guardian safety app."
        return msg
    }

    private func sendSMS(to contact: EmergencyContact) {
        let body = buildMessage()
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let phone = contact.phone.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "sms:\(phone)&body=\(body)") {
            openURL(url)
            lastSharedAt = .now
        }
    }
}

// MARK: - UIActivityViewController wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
