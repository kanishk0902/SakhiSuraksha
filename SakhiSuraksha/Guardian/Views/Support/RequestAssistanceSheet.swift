//
//  RequestAssistanceSheet.swift
//  Guardian
//
//  Builds a HelpRequest and sends it to a chosen trusted contact via SMS.
//  Contact-based only — see HelpRequestService's header comment. Used by
//  Period Emergency's "Request Assistance" and I Need Help's "Need
//  Accompaniment".
//

import SwiftUI
import SwiftData
import CoreLocation

struct RequestAssistanceSheet: View {
    let needType: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \EmergencyContact.name) private var contacts: [EmergencyContact]

    @State private var note: String = ""
    @State private var sentTo: EmergencyContact?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This sends an SMS to a trusted contact asking for help. Guardian does not have a live helper network — your contact must read the message and respond.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("What you need") {
                    Text(needType).font(.subheadline.weight(.semibold))
                }
                Section("Add a note (optional)") {
                    TextField("e.g. I'm at the bus stop on Main St", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                if contacts.isEmpty {
                    Section {
                        Text("Add a trusted contact in Settings to send a request.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section("Send to") {
                        ForEach(contacts) { contact in
                            Button {
                                send(to: contact)
                            } label: {
                                HStack {
                                    Text(contact.name)
                                    Spacer()
                                    Image(systemName: "paperplane.fill")
                                        .foregroundStyle(GuardianTheme.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Request Assistance")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func send(to contact: EmergencyContact) {
        let coord = app.location.currentLocation?.coordinate ?? LocationService.fallbackCoordinate
        let request = HelpRequest(needType: needType, note: note, coordinate: coord)
        if let url = app.helpRequests.composeSMSURL(for: request, contact: contact) {
            openURL(url)
            Haptics.tap()
            dismiss()
        }
    }
}
