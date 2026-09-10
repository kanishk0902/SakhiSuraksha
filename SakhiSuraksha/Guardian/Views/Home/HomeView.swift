//
//  HomeView.swift
//  Guardian
//
//  The safety dashboard. Immediately communicates: "I am safe, I know where I
//  am, and I can get help."
//

import SwiftUI
import CoreLocation
import SwiftData
import MapKit

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: RootView.Tab
    @AppStorage("guardian.homeGuideShown") private var guideShown = false
    @State private var showGuide = false
    @State private var showGetHelp = false
    @State private var showSafeRoute = false
    @Query private var contacts: [EmergencyContact]

    enum Route: Hashable { case getSafe, compass, share, score }
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: GuardianTheme.cardSpacing) {
                    if contacts.isEmpty { noContactsWarning }
                    confidenceCard
                    if app.emergency.isSOSActive { emergencyActiveCard }
                    if app.journey.isActive { activeJourneyCard }
                    primaryActions
                    secondaryActions
                    getHelpCard
                    nearbyResources
                }
                .padding()
            }
            .background(GuardianTheme.groupedBackground(.dark).opacity(0.0))
            .navigationTitle("Guardian")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .getSafe: GetSafeView()
                case .compass: CompassView()
                case .share:   LocationSharingView()
                case .score:   SafetyScoreView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .guardianTrailing) {
                    NavigationLink(value: Route.score) {
                        Image(systemName: "chart.bar.doc.horizontal")
                    }
                    .accessibilityLabel("Safety score details")
                }
                ToolbarItem(placement: .guardianLeading) {
                    if !guideShown {
                        Button {
                            showGuide = true
                        } label: {
                            Label("How it works", systemImage: "questionmark.circle.fill")
                                .foregroundStyle(GuardianTheme.accent)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showGuide, onDismiss: { guideShown = true }) {
            HomeGuideView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            if !guideShown { showGuide = true }
        }
    }



    // MARK: No contacts warning

    private var noContactsWarning: some View {
        Button { selection = .settings } label: {
            GuardianCard {
                HStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.title2)
                        .foregroundStyle(GuardianTheme.caution)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Emergency Contacts")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("SOS alerts need at least one contact to notify.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Confidence

    private var confidenceCard: some View {
        GuardianCard {
            VStack(spacing: 16) {
                HStack {
                    Text("Safety Confidence")
                        .font(.headline)
                    Spacer()
                    SafetyStatusBadge(state: app.safetyState)
                }
                Button {
                    path.append(.score)
                } label: {
                    SafetyGauge(score: app.confidence.score, state: app.safetyState)
                }
                .buttonStyle(.plain)

                Text(app.safetyState.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 12) {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Location").font(.caption).foregroundStyle(.secondary)
                            Text(locationText).font(.footnote.weight(.medium))
                        }
                    } icon: {
                        Image(systemName: "location.fill").foregroundStyle(GuardianTheme.accent)
                    }
                    Spacer()
                    ConnectivityChip(state: app.connectivity.state,
                                     forced: app.connectivity.isForced)
                }

                if !armedProtections.isEmpty {
                    Divider()
                    armedProtectionsRow
                }
            }
        }
    }

    /// Silent triggers (Discreet SOS, Gesture SOS) have no other visible
    /// footprint once armed — they auto-arm on foreground with zero
    /// confirmation UI otherwise, which left users with no way to tell they
    /// were actually protected. This closes that gap without adding a
    /// separate screen.
    private var armedProtections: [(String, String)] {
        var items: [(String, String)] = []
        if app.voiceTrigger.isListening { items.append(("waveform", "Discreet SOS")) }
        if app.gestureTrigger.isArmed { items.append(("hand.wave.fill", "Gesture SOS")) }
        return items
    }

    private var armedProtectionsRow: some View {
        HStack(spacing: 14) {
            ForEach(armedProtections, id: \.1) { symbol, title in
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GuardianTheme.safe)
            }
            Spacer()
            Text("Armed").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var locationText: String {
        guard let loc = app.location.currentLocation else {
            return app.location.authorizationStatus == .notDetermined
                ? "Waiting for permission…"
                : "Acquiring GPS…"
        }
        let c = loc.coordinate
        return String(format: "%.4f, %.4f · Live", c.latitude, c.longitude)
    }

    // MARK: Emergency active

    private var emergencyActiveCard: some View {
        Button {
            app.showSOSScreen = true
        } label: {
            GuardianCard {
                HStack(spacing: 12) {
                    Image(systemName: "sos")
                        .font(.title)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(GuardianTheme.emergency, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Emergency Active").font(.headline)
                        Text("Tap to open the emergency screen")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Active journey

    private var activeJourneyCard: some View {
        Group {
            if let journey = app.journey.active {
                GuardianCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Active Journey", systemImage: "figure.walk.circle.fill")
                                .font(.headline)
                            Spacer()
                            Text(journey.deviation.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(journey.deviation.mappedState.color)
                        }
                        Text("To \(journey.destinationName)")
                            .font(.subheadline)
                        ProgressView(value: journey.progress)
                            .tint(GuardianTheme.accent)
                        HStack {
                            Text("ETA \(journey.eta.formatted(date: .omitted, time: .shortened))")
                            Spacer()
                            Text("\(Int(journey.progress * 100))% complete")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Button("Open Journey") { selection = .journey }
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    // MARK: Primary actions

    private var primaryActions: some View {
        HStack(spacing: 12) {
            PrimaryActionButton(title: app.journey.isActive ? "View Journey" : "Start Journey",
                                systemImage: "figure.walk",
                                color: GuardianTheme.accent) {
                selection = .journey
            }
            Button {
                app.beginSOSCountdown()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sos")
                    Text("SOS")
                        .font(.headline)
                }
                .guardianCapsule(GuardianTheme.emergency)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Send SOS")
            .accessibilityHint("Starts a 10-second countdown you can cancel before the alert is sent")
        }
    }

    // MARK: Secondary actions

    private var secondaryActions: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                  spacing: 12) {
            SecondaryActionButton(title: "Share Location", systemImage: "location.fill.viewfinder") {
                path.append(.share)
            }
            SecondaryActionButton(title: "Get Me Safe", systemImage: "shield.lefthalf.filled") {
                path.append(.getSafe)
            }
            SecondaryActionButton(title: "Compass", systemImage: "location.north.line.fill") {
                path.append(.compass)
            }
            SecondaryActionButton(title: "Connect", systemImage: "dot.radiowaves.left.and.right") {
                selection = .connect
            }
            SecondaryActionButton(title: "Safe Route", systemImage: "shield.checkerboard",
                                  tint: GuardianTheme.safe) {
                showSafeRoute = true
            }
        }
        .sheet(isPresented: $showSafeRoute) { SafeRouteView() }
    }

    // MARK: Get Help (single entry point into the support hub)

    private var getHelpCard: some View {
        Button {
            showGetHelp = true
        } label: {
            GuardianCard {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(GuardianTheme.accent.opacity(0.14))
                        Image(systemName: "heart.text.square.fill")
                            .foregroundStyle(GuardianTheme.accent)
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Get Help").font(.headline)
                        Text("Medical, period, everyday needs, safe places & more")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .sheet(isPresented: $showGetHelp) { GetHelpHubView() }
    }

    // MARK: Nearby resources

    private var nearbyResources: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Nearby Safety Resources",
                                      systemImage: "mappin.and.ellipse")
                ForEach(nearestPlaces) { place in
                    Button {
                        navigateToPlace(place)
                    } label: {
                        HStack {
                            SafePlaceRow(place: place,
                                         distance: place.distance(from: app.location.currentLocation
                                                                   ?? CLLocation()))
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.caption)
                                .foregroundStyle(GuardianTheme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    if place.id != nearestPlaces.last?.id { Divider() }
                }
                if nearestPlaces.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text(app.safetyData.isSearching ? "Searching nearby resources…" : "Fetching nearby resources…")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            let coord = app.location.currentLocation?.coordinate ?? LocationService.fallbackCoordinate
            app.safetyData.refresh(around: coord, force: true)
        }
    }

    private func navigateToPlace(_ place: SafePlace) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    private var nearestPlaces: [SafePlace] {        let loc = app.location.currentLocation ?? CLLocation(latitude: LocationService.fallbackCoordinate.latitude,
                                                             longitude: LocationService.fallbackCoordinate.longitude)
        return app.safetyData.safePlaces
            .sorted { $0.distance(from: loc) < $1.distance(from: loc) }
            .prefix(4)
            .map { $0 }
    }
}

// MARK: - Home Guide

struct HomeGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(icon: String, color: Color, title: String, body: String)] = [
        ("shield.fill", GuardianTheme.safe,
         "Safety Confidence",
         "The ring on the home screen shows your real-time safety score (0–100). It's calculated from your GPS location, nearby safe places found via Maps, your route status, and connectivity. Tap it to see exactly what's affecting your score."),
        ("figure.walk", GuardianTheme.accent,
         "Start a Journey",
         "Tap 'Start Journey' and type any destination — a friend's house, a station, anywhere. Guardian fetches a real walking route and checks your GPS every 3 seconds. If you stray from the route, you'll get a check-in prompt."),
        ("sos", GuardianTheme.emergency,
         "SOS Button",
         "Tap the red SOS button to open the emergency screen. You get a 10-second countdown you can cancel. After countdown: an AI voice call comes to your phone and a Telegram alert with your live location goes to your contacts automatically."),
        ("location.fill.viewfinder", GuardianTheme.accent,
         "Share Location",
         "Tap 'Share Location' to send your live coordinates to a contact. Works over internet, cellular, or even nearby Guardian devices via Bluetooth mesh when you're offline."),
        ("shield.lefthalf.filled", GuardianTheme.safe,
         "Get Me Safe",
         "Tap 'Get Me Safe' to see the nearest police stations, hospitals, and public buildings ranked by distance and safety score — all from real Maps data around you."),
        ("person.2.fill", GuardianTheme.accent,
         "Emergency Contacts",
         "Go to Settings → Emergency Contacts to add the people who should hear from you in an emergency. Their numbers are used for real SMS and phone calls — not simulated."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(steps, id: \.title) { step in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: step.icon)
                                .font(.title2)
                                .foregroundStyle(step.color)
                                .frame(width: 44, height: 44)
                                .background(step.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.headline)
                                Text(step.body).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("How Guardian Works")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
