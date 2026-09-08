//
//  AppModel.swift
//  Guardian
//
//  The single coordinator injected into the SwiftUI environment. Owns all
//  services and feeds only real device data into the safety engine.
//

import Foundation
import SwiftUI
import SwiftData
import CoreLocation
import Observation

@Observable
final class AppModel {

    // MARK: Services
    let location      = LocationService()
    let connectivity  = ConnectivityService()
    let safetyData    = SafetyDataService()
    let routing       = RoutingService()
    let engine        = SafetyEngine()
    let risk          = RiskEngine()
    let journey       = JourneyService()
    let mesh          = MeshService()
    let emergency     = EmergencyService()
    let notifications = NotificationService()
    let comms         = CommunicationService()
    let nearbyPlaces  = NearbyPlacesService()
    let support       = SupportResourcesService()
    let helpRequests  = HelpRequestService()

    // MARK: Emergency state
    var pendingMedicalSOS: MedicalEmergencyType? = nil
    var showMedicalSOS = false
    var showPeriodEmergency = false
    var showINeedHelp = false
    var showSafeHavens = false
    var showWomenSupport = false
    var showReportSafetyIssue = false
    var showSafetyReports = false

    // Watch: real WatchConnectivity on iOS, stub elsewhere.
    #if os(iOS)
    let watch: any WatchService = RealWatchService()
    let voiceTrigger: any VoiceTriggerService = RealVoiceTriggerService()
    #else
    let watch: any WatchService = MockWatchService()
    let voiceTrigger: any VoiceTriggerService = MockVoiceTriggerService()
    #endif

    // MARK: Discreet SOS
    var discreetSOSPending = false
    var discreetSOSCountdownSeconds = 0
    private var discreetCountdownTask: Task<Void, Never>?

    // MARK: Persistence
    var modelContext: ModelContext?

    // MARK: Shared derived state
    var confidence: SafetyConfidence = SafetyConfidence(score: 50, state: .passive, signals: [])
    var safetyState: SafetyState { confidence.state }

    // MARK: Presentation
    var showSOSScreen = false

    private var hasStarted = false

    // MARK: Custom SOS trigger
    /// Number of rapid taps on the shield button to trigger SOS. 0 = disabled.
    var sosTapCount: Int {
        get { UserDefaults.standard.object(forKey: "guardian.sosTapCount") as? Int ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: "guardian.sosTapCount") }
    }

    // MARK: Check-in
    var pendingCheckIn = false
    var checkInPrompt = "Your journey has changed significantly. Are you safe?"
    var unansweredCheckIns = 0
    private var lastCheckInAt: Date?
    private var lastConfirmedSafeAt: Date?
    private var lastCheckInDismissedAt: Date?
    /// How long to wait after a check-in is dismissed before deviation can
    /// prompt another one, even if the user's position is still off-route.
    /// Without this, "I'm Safe" gets immediately undone by the next tick's
    /// deviation reading and the same prompt reappears every few seconds.
    private let deviationCheckInCooldown: TimeInterval = 120

    // MARK: Watch events
    var latestWatchEvent: WatchSafetyEvent?

    private var tickTask: Task<Void, Never>?

    // MARK: Lifecycle

    func start(context: ModelContext) {
        guard !hasStarted else { return }
        hasStarted = true
        modelContext = context

        mesh.configure(modelContext: context)
        mesh.start()

        connectivity.start()
        location.requestPermission()
        location.startContinuous()
        ensureSeedData(context: context)

        watch.onEvent { [weak self] event in self?.ingest(watchEvent: event) }

        connectivity.onStateChange = { [weak self] in
            self?.mesh.flushQueue()
            if let state = self?.connectivity.state {
                self?.comms.flushQueued(connectivity: state, mesh: self?.mesh)
                _ = state
            }
        }

        Task { await notifications.refreshStatus() }
        recomputeSafety()
        startTicking()
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                self?.tick()
            }
        }
    }

    private func tick() {
        let coord = location.currentLocation?.coordinate ?? LocationService.fallbackCoordinate
        safetyData.refresh(around: coord)

        if journey.isActive, let loc = location.currentLocation {
            let level = journey.update(location: loc)
            evaluateDeviation(level)
        }

        if pendingCheckIn, let last = lastCheckInAt,
           Date.now.timeIntervalSince(last) > 25 {
            unansweredCheckIns += 1
            lastCheckInAt = .now
        }

        recomputeSafety()
    }

    // MARK: Safety context (real data only)

    func buildContext() -> SafetyContext {
        let loc = location.currentLocation
        let places = loc != nil ? safetyData.safePlaces : []
        let nearest = loc.map { l in places.map { $0.distance(from: l) }.min() } ?? nil

        var context = SafetyContext()
        context.date                   = .now
        context.connectivity           = displayConnectivity
        context.onJourney              = journey.isActive
        context.deviation              = journey.active?.deviation ?? .normal
        context.nearbySafePlaceCount   = places.count
        context.nearestSafePlaceMeters = nearest
        context.cctvCoveragePercent    = 0   // no real CCTV data source
        context.nearbyIncidentCount    = safetyData.incidents.count
        context.unusualMovement        = false
        context.userConfirmedSafe = {
            guard let t = lastConfirmedSafeAt else { return false }
            return Date.now.timeIntervalSince(t) < 300
        }()
        context.watchEvent        = latestWatchEvent
        context.hardwareEvent     = nil
        context.explicitEmergency = emergency.isSOSActive
        return context
    }

    var displayConnectivity: ConnectivityState {
        if connectivity.state.hasInternet { return connectivity.state }
        if mesh.hasConnectedPeers { return .mesh }
        return .offline
    }

    func recomputeSafety() {
        let previous = confidence.state
        var result = engine.evaluate(buildContext())

        let escalated = risk.escalatedState(from: result.state,
                                             unansweredCheckIns: unansweredCheckIns)
        if escalated.severity > result.state.severity {
            result.state = escalated
            result.signals.append(.init(kind: .userConfirmation,
                                        label: "Unanswered check-in", impact: -12))
        }
        confidence = result

        let inCooldown = lastCheckInDismissedAt.map {
            Date.now.timeIntervalSince($0) < deviationCheckInCooldown
        } ?? false
        if risk.shouldPromptCheckIn(previous: previous, next: result.state),
           !emergency.isSOSActive, !inCooldown {
            promptCheckIn()
        }
    }

    private func evaluateDeviation(_ level: DeviationLevel) {
        guard level.severity() >= DeviationLevel.cautious.severity(), !pendingCheckIn else { return }
        // Don't re-prompt immediately after the user just dismissed one —
        // without this, a still-off-route position re-triggers the alarm
        // within one tick of "I'm Safe"/"Taking Another Route", making the
        // same prompt appear to repeat every few seconds.
        if let last = lastCheckInDismissedAt, Date.now.timeIntervalSince(last) < deviationCheckInCooldown {
            return
        }
        notifications.notify(.deviation, body: "Your route has changed significantly.")
        promptCheckIn()
    }

    // MARK: Check-in responses

    func promptCheckIn() {
        guard !pendingCheckIn else { return }
        pendingCheckIn = true
        lastCheckInAt = .now
        notifications.notify(.checkIn, body: checkInPrompt)
        Haptics.warning()
    }

    func respondSafe() {
        pendingCheckIn = false
        unansweredCheckIns = 0
        lastConfirmedSafeAt = .now
        lastCheckInDismissedAt = .now
        journey.acknowledgeNewRoute()
        recomputeSafety()
        Haptics.success()
    }

    func respondTakingAnotherRoute() {
        pendingCheckIn = false
        unansweredCheckIns = 0
        lastCheckInDismissedAt = .now
        journey.acknowledgeNewRoute()
        recomputeSafety()
    }

    func respondNeedHelp() {
        pendingCheckIn = false
        activateSOS(message: nil, source: .journeyTimeout)
    }

    // MARK: SOS — unified entry point
    // Apple Watch / fall detection plug in here later via EmergencySource.

    @discardableResult
    func triggerSOS(source: EmergencySource, message: String? = nil) -> EmergencyPacket? {
        let msg: String
        switch source {
        case .medicalSOS:      msg = message ?? "Medical emergency. I need help."
        case .discreetPhrase:  msg = message ?? "I need help. This is a discreet SOS alert."
        case .journeyTimeout:  msg = message ?? "I haven't reached my destination. Please check on me."
        default:               msg = message ?? nil ?? "I need help. This is an automated Guardian alert with my location."
        }
        return activateSOS(message: msg, source: source)
    }

    // MARK: SOS

    @discardableResult
    func activateSOS(message: String?, source: EmergencySource = .manual) -> EmergencyPacket? {
        guard let context = modelContext else { return nil }
        let profile = fetchProfile(context: context)
        let msg = message ?? profile?.emergencyMessage
            ?? "I need help. This is an automated Guardian alert with my location."
        let sender = (profile?.name.isEmpty == false ? profile!.name : "Guardian User")

        Haptics.emergency()
        showSOSScreen = true
        location.startContinuous()
        let coord = location.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let packet = emergency.activateSOS(
            location: coord,
            safetyState: .emergency,
            riskScore: confidence.score,
            message: msg,
            senderID: sender,
            mesh: mesh,
            context: context,
            source: source)
        let mapLink: String
        if let loc = location.currentLocation {
            mapLink = String(format: "https://maps.apple.com/?q=%.5f,%.5f",
                             loc.coordinate.latitude, loc.coordinate.longitude)
        } else {
            mapLink = "location updating…"
        }
        notifications.notify(.emergency, body: "🚨 Emergency active. Tap to open Guardian. Location: \(mapLink)")
        recomputeSafety()
        return packet
    }

    func resolveSOS() {
        emergency.resolveSOS()
        latestWatchEvent = nil
        showSOSScreen = false
        recomputeSafety()
        Haptics.success()
    }

    // MARK: Discreet SOS
    // Foreground-only: RootView stops listening when the app leaves the
    // foreground (iOS does not allow unrestricted background voice
    // recognition). The phrase is an exact (case-insensitive) match — Guardian
    // never claims to detect a "dangerous tone."

    func startDiscreetListening(phrase: String, countdownSeconds: Int = 10) {
        voiceTrigger.startListening(phrase: phrase) { [weak self] _ in
            Task { @MainActor in self?.beginDiscreetCountdown(seconds: countdownSeconds) }
        }
    }

    func stopDiscreetListening() {
        voiceTrigger.stopListening()
    }

    func beginDiscreetCountdown(seconds: Int = 10) {
        guard !discreetSOSPending else { return }
        discreetSOSPending = true
        discreetSOSCountdownSeconds = seconds
        discreetCountdownTask?.cancel()
        discreetCountdownTask = Task { [weak self] in
            while let self, self.discreetSOSCountdownSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self.discreetSOSCountdownSeconds -= 1
            }
            guard let self, self.discreetSOSPending else { return }
            self.discreetSOSPending = false
            self.triggerSOS(source: .discreetPhrase)
        }
    }

    func cancelDiscreetSOS() {
        discreetCountdownTask?.cancel()
        discreetCountdownTask = nil
        discreetSOSPending = false
    }

    // MARK: Watch events

    func ingest(watchEvent event: WatchSafetyEvent) {
        latestWatchEvent = event
        if event.kind == .sos {
            activateSOS(message: "Apple Watch SOS triggered.", source: .appleWatch)
        } else { recomputeSafety() }
    }

    // MARK: Data helpers

    func fetchProfile(context: ModelContext) -> UserProfile? {
        try? context.fetch(FetchDescriptor<UserProfile>()).first
    }

    private func ensureSeedData(context: ModelContext) {
        if (try? context.fetch(FetchDescriptor<UserProfile>()))?.isEmpty ?? true {
            context.insert(UserProfile(name: ""))
            try? context.save()
        }
        // Remove any previously seeded fake contacts ("Mom", "Aisha") from old builds.
        let fakeNames: Set<String> = ["Mom", "Aisha"]
        let allContacts = (try? context.fetch(FetchDescriptor<EmergencyContact>())) ?? []
        let fakes = allContacts.filter {
            fakeNames.contains($0.name) && ($0.phone == "+1 555 0101" || $0.phone == "+1 555 0134")
        }
        fakes.forEach { context.delete($0) }
        if !fakes.isEmpty { try? context.save() }
    }
}

extension DeviationLevel {
    func severity() -> Int {
        switch self {
        case .normal:    return 0
        case .minor:     return 1
        case .cautious:  return 2
        case .alert:     return 3
        case .emergency: return 4
        }
    }
}
