//
//  ShareDestinationButton.swift
//  Guardian
//
//  "I'm going here" — lets the user tell a trusted contact where they're
//  headed via SMS. Reuses the same sms: composition idiom as
//  JourneySetupView.startJourney() and SOSView's quick actions.
//

import SwiftUI
import SwiftData
import CoreLocation

struct ShareDestinationButton: View {
    let destinationName: String
    let coordinate: CLLocationCoordinate2D
    @Environment(\.openURL) private var openURL
    @Query(sort: \EmergencyContact.name) private var contacts: [EmergencyContact]
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            Label("I'm Going Here", systemImage: "location.fill.viewfinder")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.plain)
        .confirmationDialog("Tell a trusted contact", isPresented: $showPicker, titleVisibility: .visible) {
            ForEach(contacts) { contact in
                Button(contact.name) { share(with: contact) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // A confirmationDialog button can't navigate anywhere once
            // tapped, so when there are no contacts this shows guidance as
            // plain text instead of a button that looks actionable but does
            // nothing when pressed.
            if contacts.isEmpty {
                Text("Add a trusted contact in Settings first.")
            }
        }
    }

    private func share(with contact: EmergencyContact) {
        let locStr = "https://maps.apple.com/?q=\(coordinate.latitude),\(coordinate.longitude)"
        let body = "I'm going to \(destinationName). Track me: \(locStr)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let phone = contact.phone.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "sms:\(phone)&body=\(body)") { openURL(url) }
        Haptics.tap()
    }
}
