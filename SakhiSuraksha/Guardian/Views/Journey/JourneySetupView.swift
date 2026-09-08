//
//  JourneySetupView.swift
//  Guardian
//
//  Start a journey: search any real address/place, pick a trusted contact,
//  then build a live Safety Corridor with a real MapKit walking route.
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import UIKit

// MARK: - Address search completer wrapper

@Observable
final class AddressSearchService: NSObject, MKLocalSearchCompleterDelegate {
    var query: String = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var results: [MKLocalSearchCompletion] = []
    private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request(completion: completion)
        let result = try? await MKLocalSearch(request: request).start()
        return result?.mapItems.first?.placemark.coordinate
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { self.results = completer.results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { self.results = [] }
    }
}

// MARK: - View

struct JourneySetupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \EmergencyContact.name) private var contacts: [EmergencyContact]

    @State private var searchService = AddressSearchService()
    @State private var destinationName: String = ""
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var selectedContact: EmergencyContact?
    @State private var isPreparing = false
    @State private var showSearchResults = false

    var body: some View {
        ScrollView {
            VStack(spacing: GuardianTheme.cardSpacing) {
                introCard
                destinationCard
                contactCard
                startButton
            }
            .padding()
        }
        .onChange(of: searchService.query) { _, new in
            showSearchResults = !new.isEmpty
        }
    }

    // MARK: Intro

    private var introCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Protected Journey", systemImage: "shield.checkered")
                    .font(.headline)
                Text("Search for any destination — Guardian will fetch a real walking route and monitor your safety every 3 seconds.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Destination search

    private var destinationCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 16) {
                GuardianSectionHeader(title: "Where are you going?",
                                      systemImage: "magnifyingglass")

                HStack {
                    Image(systemName: "location.circle.fill").foregroundStyle(GuardianTheme.safe)
                    VStack(alignment: .leading) {
                        Text("From").font(.caption).foregroundStyle(.secondary)
                        Text("Current location").font(.subheadline.weight(.medium))
                    }
                    Spacer()
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "flag.checkered.circle.fill")
                            .foregroundStyle(GuardianTheme.accent)
                        TextField("Search destination…", text: $searchService.query)
                            .autocorrectionDisabled()
                            .onSubmit { showSearchResults = false }
                        if !searchService.query.isEmpty {
                            Button {
                                searchService.query = ""
                                destinationName = ""
                                destinationCoordinate = nil
                                showSearchResults = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if showSearchResults && !searchService.results.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(searchService.results.prefix(6), id: \.title) { result in
                                Button {
                                    Task { await selectResult(result) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if !result.subtitle.isEmpty {
                                            Text(result.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 10)
                                }
                                if result.title != searchService.results.prefix(6).last?.title {
                                    Divider()
                                }
                            }
                        }
                    }

                    if let name = destinationCoordinate != nil ? destinationName : nil {
                        Label("Destination set: \(name)", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(GuardianTheme.safe)
                    }
                }
            }
        }
    }

    // MARK: Contact

    private var contactCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Trusted Contact (optional)",
                                      systemImage: "person.badge.shield.checkmark")
                if contacts.isEmpty {
                    Text("Add contacts in Settings → Emergency Contacts to notify them when you travel.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Menu {
                        Button("None") { selectedContact = nil }
                        ForEach(contacts) { contact in
                            Button(contact.name) { selectedContact = contact }
                        }
                    } label: {
                        HStack {
                            Text(selectedContact?.name ?? "None")
                                .foregroundStyle(selectedContact == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Start

    private var canStart: Bool {
        destinationCoordinate != nil && !isPreparing
    }

    private var startButton: some View {
        VStack(spacing: 8) {
            PrimaryActionButton(
                title: isPreparing ? "Preparing Safety Corridor…" : "Start Journey",
                systemImage: "play.fill",
                color: canStart ? GuardianTheme.accent : Color.secondary
            ) {
                guard canStart else { return }
                Task { await startJourney() }
            }
            .disabled(!canStart || isPreparing)
            .opacity(canStart ? 1 : 0.6)

            if isPreparing {
                Label("Preparing Safety Corridor…", systemImage: "location.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    private func selectResult(_ result: MKLocalSearchCompletion) async {
        guard let coord = await searchService.resolve(result) else { return }
        destinationCoordinate = coord
        destinationName = result.title
        searchService.query = result.title
        showSearchResults = false
    }

    private func startJourney() async {
        guard let coord = destinationCoordinate else { return }
        let origin = app.location.currentLocation?.coordinate ?? LocationService.fallbackCoordinate
        isPreparing = true
        defer { isPreparing = false }

        app.location.startContinuous()
        let route = await app.routing.route(from: origin, to: coord)
        let alternates = await app.routing.alternates(from: origin, to: coord)

        _ = await app.journey.start(originName: "Current location",
                              destinationName: destinationName,
                              origin: origin,
                              destination: coord,
                              contactName: selectedContact?.name,
                              route: route,
                              alternates: alternates,
                              data: app.safetyData)

        let record = JourneyRecord(originName: "Current location",
                                   destinationName: destinationName,
                                   contactName: selectedContact?.name)
        context.insert(record)
        try? context.save()

        if let contact = selectedContact {
            let locStr: String
            if let coord = app.location.currentLocation?.coordinate {
                locStr = "https://maps.apple.com/?q=\(coord.latitude),\(coord.longitude)"
            } else {
                locStr = "location unavailable"
            }
            let body = "I've started a journey to \(destinationName). Track me: \(locStr)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let phone = contact.phone.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "sms:\(phone)&body=\(body)") {
                await UIApplication.shared.open(url)
            }
            app.notifications.notify(.checkIn,
                                     body: "\(contact.name) will be kept updated on your journey.")
        }
        app.recomputeSafety()
        Haptics.success()
    }
}
