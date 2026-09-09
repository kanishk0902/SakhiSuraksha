//
//  ActiveNavigationView.swift
//  Guardian
//
//  Immersive, full-screen turn-by-turn navigation — pushed from
//  ActiveJourneyView via "Start Navigation", not a replacement for it.
//  Everything shown here is real: turn-by-turn instructions and distance
//  come from JourneyService/RoutingService's already-computed step data,
//  the safety score is the same routeSafetyScore ActiveJourneyView shows,
//  and deviation/reroute reuse the existing conservative deviation
//  classifier — nothing here is a second, parallel safety system.
//
//  "Ending Navigation" only leaves this immersive screen; it does not end
//  the underlying journey. Ending the journey itself stays solely on
//  ActiveJourneyView's own "End Journey" action.
//

import SwiftUI
import MapKit
import SwiftData

struct ActiveNavigationView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var voice = NavigationVoiceService()
    @State private var isFollowingCamera = true
    @State private var headingUp = true
    @State private var showEndNavConfirm = false
    @State private var showArrival = false
    @State private var isMuted = false

    // Dynamic safety rerouting (periodic rescoring of current vs alternates).
    @State private var currentRouteScore: Int?
    @State private var saferAlternateIndex: Int?
    @State private var saferAlternateScore: Int?

    // Deviation → real reroute, with a cooldown so a single deviation escalation
    // doesn't fire repeated MapKit requests while the user is still off-route.
    @State private var lastRerouteAt: Date?
    @State private var isRerouting = false

    var body: some View {
        Group {
            if let journey = app.journey.active {
                navigationBody(journey)
            } else {
                ContentUnavailableView("No active journey", systemImage: "location.slash")
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { isMuted = voice.isMuted }
        .task(id: app.journey.active?.id) { await startRescoreLoop() }
    }

    private func navigationBody(_ journey: LiveJourney) -> some View {
        let allRoutes = [journey.corridor.routeCoordinates] + journey.corridor.alternateRoutes

        return ZStack {
            GuardianMap(routes: allRoutes,
                        safePlaces: [],
                        checkpoints: journey.corridor.checkpoints,
                        destination: journey.destination,
                        userPosition: app.location.currentLocation?.coordinate,
                        userHeading: app.location.navigationHeading(fallbackBearingTo: journey.destination),
                        minimalOverlays: true,
                        followsUser: isFollowingCamera,
                        headingUp: headingUp,
                        onUserPanned: { isFollowingCamera = false })
                .ignoresSafeArea()

            VStack {
                instructionCard(journey)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                if isRerouting || journey.deviation.severity() >= DeviationLevel.cautious.severity() {
                    deviationBanner
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                Spacer()

                HStack(alignment: .bottom) {
                    Spacer()
                    sideControls
                        .padding(.trailing, 12)
                }

                bottomPanel(journey)
                    .padding(12)
            }
        }
        .onChange(of: journey.currentStepIndex) { _, _ in
            voice.announceIfNeeded(step: journey.currentStep,
                                   stepIndex: journey.currentStepIndex,
                                   distanceMeters: journey.distanceToNextStepMeters)
        }
        .onChange(of: journey.deviation) { _, newValue in
            guard newValue.severity() >= DeviationLevel.cautious.severity() else { return }
            attemptReroute(journey)
        }
        .onChange(of: hasArrived(journey)) { _, arrived in
            if arrived { showArrival = true }
        }
        .confirmationDialog("End navigation?", isPresented: $showEndNavConfirm, titleVisibility: .visible) {
            Button("End Navigation", role: .destructive) { dismiss() }
            Button("Keep Navigating", role: .cancel) {}
        } message: {
            Text("Your journey stays active — this only closes turn-by-turn navigation.")
        }
        .sheet(isPresented: $showArrival) {
            ArrivalView(journey: journey) {
                app.completeJourney(completed: true, context: context)
                showArrival = false
                dismiss()
            }
            .interactiveDismissDisabled()
        }
    }

    // MARK: Instruction card

    private func instructionCard(_ journey: LiveJourney) -> some View {
        let step = journey.currentStep
        let direction = step.map { TurnDirection.infer(from: $0.instructions) } ?? .straight
        let nextStep = journey.corridor.steps[safe: (journey.currentStepIndex ?? -1) + 1]

        return GuardianCard {
            HStack(spacing: 16) {
                Image(systemName: direction.symbol)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(GuardianTheme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    if let step {
                        Text(step.instructions)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                        if let distance = journey.distanceToNextStepMeters {
                            Text(distanceText(distance))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let nextStep {
                            Text("Then \(nextStep.instructions)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("Continue toward \(journey.destinationName)")
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GuardianTheme.cornerRadius, style: .continuous))
    }

    private func distanceText(_ meters: Double) -> String {
        meters < 1000 ? "In \(Int(meters)) m" : String(format: "In %.1f km", meters / 1000)
    }

    // MARK: Deviation / reroute

    private var deviationBanner: some View {
        GuardianCard {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(GuardianTheme.alert)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Route deviation detected").font(.subheadline.weight(.semibold))
                    Text(isRerouting ? "Recalculating your route…" : "Continuing to monitor your position.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func attemptReroute(_ journey: LiveJourney) {
        guard !isRerouting, let location = app.location.currentLocation else { return }
        if let last = lastRerouteAt, Date.now.timeIntervalSince(last) < 30 { return }
        lastRerouteAt = .now
        isRerouting = true
        Task {
            await app.journey.recomputeRoute(from: location.coordinate, routing: app.routing)
            isRerouting = false
            if let contactName = journey.contactName {
                app.notifications.notify(.deviation, body: "Route recalculated. Still sharing your trip with \(contactName).")
            }
        }
    }

    // MARK: Dynamic safety rerouting

    private func startRescoreLoop() async {
        while !Task.isCancelled {
            await rescoreRoutes()
            try? await Task.sleep(for: .seconds(20))
        }
    }

    private func rescoreRoutes() async {
        guard let journey = app.journey.active else { return }
        let allRoutes = [journey.corridor.routeCoordinates] + journey.corridor.alternateRoutes
        guard allRoutes.count > 1 else { return }
        let provider = LocalRouteSafetyProvider(data: app.safetyData)
        var scores: [Int] = []
        for route in allRoutes {
            scores.append((try? await provider.safetyScore(for: route)) ?? 50)
        }
        currentRouteScore = scores.first
        guard let current = scores.first else { return }
        // Meaningful threshold only — avoid surfacing a "safer route" for a
        // marginal, noise-level score difference.
        if let bestAlternateIndex = scores.enumerated().dropFirst().max(by: { $0.element < $1.element })?.offset,
           scores[bestAlternateIndex] - current > 10 {
            saferAlternateIndex = bestAlternateIndex
            saferAlternateScore = scores[bestAlternateIndex]
        } else {
            saferAlternateIndex = nil
            saferAlternateScore = nil
        }
    }

    private func takeSaferRoute(_ journey: LiveJourney) {
        guard let index = saferAlternateIndex else { return }
        // Alternates carry no turn-by-turn steps (RoutingService.alternates
        // returns coordinates only) — clearing steps here is honest about
        // that gap; the next deviation-triggered recomputeRoute (or simply
        // continuing to move) will restore real turn-by-turn guidance for
        // the new path once a stepped route is available again.
        let alternateIndex = index - 1
        guard journey.corridor.alternateRoutes.indices.contains(alternateIndex) else { return }
        journey.corridor.routeCoordinates = journey.corridor.alternateRoutes[alternateIndex]
        journey.corridor.steps = []
        journey.currentStepIndex = nil
        if let score = saferAlternateScore {
            journey.corridor.routeSafetyScore = score
        }
        saferAlternateIndex = nil
        saferAlternateScore = nil
        Haptics.success()
    }

    // MARK: Side controls

    private var sideControls: some View {
        VStack(spacing: 14) {
            circleButton(systemImage: "location.fill", active: isFollowingCamera) {
                isFollowingCamera = true
            }
            circleButton(systemImage: headingUp ? "location.north.line.fill" : "location.north.fill",
                        active: false) {
                headingUp.toggle()
            }
            circleButton(systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        active: false) {
                voice.isMuted.toggle()
                isMuted = voice.isMuted
            }
        }
    }

    private func circleButton(systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? .white : .primary)
                .frame(width: 46, height: 46)
                .background(active ? GuardianTheme.accent : Color(.systemBackground).opacity(0.9),
                           in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: Bottom panel

    private func bottomPanel(_ journey: LiveJourney) -> some View {
        let remaining = app.location.currentLocation.flatMap {
            JourneyService.remainingRouteDistanceMeters(route: journey.corridor.routeCoordinates, from: $0)
        }

        return VStack(spacing: 10) {
            if saferAlternateIndex != nil, let score = saferAlternateScore {
                saferRouteBanner(currentScore: currentRouteScore ?? journey.corridor.routeSafetyScore,
                                saferScore: score) { takeSaferRoute(journey) }
            }

            GuardianCard {
                VStack(spacing: 10) {
                    HStack {
                        Label("Safe Route", systemImage: "shield.lefthalf.filled")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("Safety Score: \(journey.corridor.routeSafetyScore)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(journey.corridor.routeSafetyScore >= 65 ? GuardianTheme.safe : GuardianTheme.caution)
                    }
                    if let contactName = journey.contactName {
                        HStack {
                            Image(systemName: "person.fill.checkmark").font(.caption2)
                            Text("Sharing with \(contactName)").font(.caption2)
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formattedRemaining(journey)).font(.headline)
                            Text(remaining.map(distanceOnlyText) ?? "—")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("ETA").font(.caption2).foregroundStyle(.secondary)
                            Text(journey.eta.formatted(date: .omitted, time: .shortened))
                                .font(.headline)
                        }
                    }
                    HStack(spacing: 10) {
                        SecondaryActionButton(title: "SOS", systemImage: "sos",
                                              tint: GuardianTheme.emergency) {
                            app.activateSOS(message: nil)
                        }
                        SecondaryActionButton(title: "Safe Havens", systemImage: "shield.lefthalf.filled",
                                              tint: GuardianTheme.safe) {
                            app.showSafeHavens = true
                        }
                        SecondaryActionButton(title: "End Navigation", systemImage: "xmark.circle",
                                              tint: .secondary) {
                            showEndNavConfirm = true
                        }
                    }
                }
            }
        }
    }

    private func saferRouteBanner(currentScore: Int, saferScore: Int, action: @escaping () -> Void) -> some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Safer route available", systemImage: "exclamationmark.shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GuardianTheme.caution)
                HStack {
                    Text("Current: \(currentScore)").font(.caption).foregroundStyle(.secondary)
                    Text("→").foregroundStyle(.secondary)
                    Text("Alternative: \(saferScore)").font(.caption.weight(.semibold)).foregroundStyle(GuardianTheme.safe)
                }
                Button("Take safer route", action: action)
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private func formattedRemaining(_ journey: LiveJourney) -> String {
        let minutes = max(0, Int(journey.remaining / 60))
        return "\(minutes) min"
    }

    private func distanceOnlyText(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters)) m remaining" : String(format: "%.1f km remaining", meters / 1000)
    }

    // MARK: Arrival

    private func hasArrived(_ journey: LiveJourney) -> Bool {
        guard let location = app.location.currentLocation else { return false }
        let destination = CLLocation(latitude: journey.destination.latitude, longitude: journey.destination.longitude)
        return location.distance(from: destination) < 30
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Arrival

private struct ArrivalView: View {
    let journey: LiveJourney
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(GuardianTheme.safe)
            Text("You've arrived").font(.title2.weight(.bold))

            GuardianCard {
                VStack(alignment: .leading, spacing: 10) {
                    labeledRow("Destination", journey.destinationName)
                    labeledRow("Journey", "\(Int(journey.plannedDuration / 60)) min · \(journey.originName)")
                    labeledRow("Safety Score", "\(journey.corridor.routeSafetyScore)")
                }
            }

            if let contactName = journey.contactName {
                Text("A location link was shared with \(contactName) when this journey started.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            PrimaryActionButton(title: "Done", systemImage: "checkmark", color: GuardianTheme.safe) {
                onDone()
            }
        }
        .padding()
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold))
        }
    }
}
