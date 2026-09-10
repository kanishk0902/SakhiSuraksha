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
    let alerts        = AlertService()
    let guardianService = CommunityGuardianService()
    /// Shared instance (not per-view) so the ML location-safety score can
    /// feed the main SafetyEngine score, not just SafetyScoreView's own
    /// separate ML card. SafeRouteView/SafetyScoreView still hold their own
    /// local instances for route search, which is unrelated to this feed.
    let safeRouting   = SafeRoutingService()

    // MARK: Emergency state
    // Safe Havens is triggered contextually mid-journey (ActiveNavigationView)
    // as well as from the Get Help hub, so it stays a shared AppModel flag
    // rather than local view state. Other support screens (Medical SOS,
    // Period Emergency, I Need Help, Women's Support, Report Safety Issue,
    // Safety Reports) are reached exclusively through GetHelpHubView's own
    // local state — no separate AppModel flag needed for those.
    var showSafeHavens = false

    // MARK: Community Guardian presentation
    // showCommunityGuardianStatus is set from SOSView during an active,
    // guardian-assisted emergency. showGuardianDashboard is set when an
    // incoming guardian request notification arrives (see start(context:)
    // below) so it can interrupt regardless of what screen is open.
    var showCommunityGuardianStatus = false
    var showGuardianDashboard = false

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

    // MARK: Gesture SOS (phone-side, no Watch needed)
    let gestureTrigger = GestureTriggerService()
    var gestureSOSPending = false
    var gestureSOSCountdownSeconds = 0
    private var gestureCountdownTask: Task<Void, Never>?
    /// Persisted preference — whether gesture arming should auto-resume when
    /// Guardian returns to the foreground. Mirrors the Watch app's autoArm.
    var gestureSOSAutoArm: Bool {
        get { UserDefaults.standard.object(forKey: "guardian.gestureSOS.autoArm") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "guardian.gestureSOS.autoArm") }
    }
    var gestureSOSCountdownDuration: Int {
        get { UserDefaults.standard.object(forKey: "guardian.gestureSOS.countdown") as? Int ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: "guardian.gestureSOS.countdown") }
    }

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
    var checkInPrompt = "Checking in — are you safe?"
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
        guardianService.configure(modelContext: context, mesh: mesh)
        mesh.onPacketReceived = { [weak self] packet in
            guard let self else { return }
            let hadRequest = guardianService.incomingRequest != nil
            guardianService.handle(packet)
            // A new incoming guardian request needs to interrupt, not wait
            // for the user to happen to open Settings — this was previously
            // only visible by manually navigating to GuardianDashboardView.
            if !hadRequest, guardianService.incomingRequest != nil {
                notifications.notify(.guardianRequest,
                                     body: "Someone nearby needs assistance. Tap to view the request.")
                showGuardianDashboard = true
            }
        }

        connectivity.start()
        location.requestPermission()
        location.startContinuous()
        ensureSeedData(context: context)
        completeQueuedBackgroundSOS(context: context)

        watch.onEvent { [weak self] event in self?.ingest(watchEvent: event) }

        // "Always" authorization arrives asynchronously (system prompt), so
        // background tracking is (re)applied here once it actually lands —
        // requesting it in journeyDidStart alone would race the still-pending
        // grant and leave background updates off for the rest of the trip.
        location.onAuthorizedAlways = { [weak self] in
            guard let self, self.journey.isActive else { return }
            self.location.setBackgroundTracking(true)
        }

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

    // MARK: Journey background tracking
    // A journey is the one time Guardian needs to keep watching location
    // after the app is backgrounded — that's the whole safety promise of
    // "start a journey and I'll know if something goes wrong." Outside of an
    // active journey, background GPS is switched off again.

    /// Call once a journey has started. Requests "Always" location (a no-op
    /// if already denied/granted) and switches on background delivery plus a
    /// persistent, discreetly-worded notification so the user has visible
    /// confirmation Guardian is still watching with the screen off.
    func journeyDidStart(destinationName: String) {
        location.requestAlwaysPermission()
        location.setBackgroundTracking(true)
        notifications.postOngoingJourneyNotification(destinationName: destinationName)
    }

    func journeyDidEnd() {
        location.setBackgroundTracking(false)
        notifications.clearOngoingJourneyNotification()
    }

    /// Ends the active journey for real — marks its JourneyRecord
    /// completed/cancelled, releases background tracking, and updates
    /// safety state. Lifted out of ActiveJourneyView so both it and the
    /// active-navigation arrival flow call the exact same completion path
    /// rather than duplicating this logic.
    func completeJourney(completed: Bool, context: ModelContext) {
        guard let journey = self.journey.active else { return }
        let record = try? context.fetch(FetchDescriptor<JourneyRecord>())
            .first { $0.originName == journey.originName && $0.destinationName == journey.destinationName && $0.endedAt == nil }
        record?.endedAt = .now
        record?.status = completed ? .completed : .cancelled
        try? context.save()
        journeyDidEnd()
        if completed {
            self.journey.complete()
            Haptics.success()
        } else {
            self.journey.cancel()
        }
        recomputeSafety()
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
            checkNearingDestination(journey.active)
        }

        if pendingCheckIn, let last = lastCheckInAt,
           Date.now.timeIntervalSince(last) > 25 {
            unansweredCheckIns += 1
            lastCheckInAt = .now
        }

        refreshMLAreaSafetyIfDue()
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
        // Only trust the last-fetched ML score if it's still for (roughly)
        // this location — a stale score from a previous, distant location
        // would be worse than no signal at all. safeRouting.locationSafety
        // is nil whenever nothing was ever successfully fetched, outside
        // coverage, or offline — buildContext never guesses in that case.
        if let loc, let safety = safeRouting.locationSafety,
           CLLocation(latitude: safety.lat, longitude: safety.lon).distance(from: loc) < 300 {
            context.mlAreaSafetyScore = safety.safetyScoreRounded
        }
        return context
    }

    /// Refreshes the ML area-safety score used by buildContext(). Runs on
    /// its own slow cadence (not every 3s tick) since it's a real network
    /// call to a local dev server — tick() only triggers this every
    /// mlAreaSafetyRefreshInterval, and buildContext() reuses whatever was
    /// last fetched in between (nil if nothing has succeeded yet).
    private var lastMLAreaSafetyFetchAt: Date?
    private let mlAreaSafetyRefreshInterval: TimeInterval = 120
    private func refreshMLAreaSafetyIfDue() {
        guard let loc = location.currentLocation else { return }
        if let last = lastMLAreaSafetyFetchAt, Date.now.timeIntervalSince(last) < mlAreaSafetyRefreshInterval {
            return
        }
        lastMLAreaSafetyFetchAt = .now
        Task {
            await safeRouting.fetchLocationSafety(at: loc.coordinate)
            recomputeSafety()
        }
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
        // Only prompt while a journey is actually active — the sheet's copy
        // and actions ("I'm Safe" / "Taking Another Route") only make sense
        // mid-journey. Without this guard, a low score from something
        // unrelated to a journey (e.g. it's simply late at night, or GPS/
        // safe-place data hasn't loaded yet right after launch) could pop
        // this sheet on cold start with nothing to actually check in about.
        if journey.isActive,
           risk.shouldPromptCheckIn(previous: previous, next: result.state),
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
        notifications.notify(.deviation, body: "You've moved off your planned route.")
        promptCheckIn()
    }

    /// Fires the "Almost there" notification once per journey when progress
    /// crosses 90% — a quiet nudge that arrival is close, matching what a
    /// nav app would surface, without repeating on every subsequent tick.
    private var notifiedNearingForJourneyID: UUID?
    private func checkNearingDestination(_ journey: LiveJourney?) {
        guard let journey, journey.progress >= 0.9,
              notifiedNearingForJourneyID != journey.id else { return }
        notifiedNearingForJourneyID = journey.id
        notifications.notify(.etaNearing, body: "Almost there — you're close to \(journey.destinationName).")
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

    /// Seconds a user gets to cancel before a manually-tapped SOS actually fires.
    static let sosCountdownDuration = 10

    /// Remaining seconds on the pre-activation countdown, or nil when no
    /// countdown is running. Lives on the model rather than in SOSView so that
    /// every SOS button in the app shares one countdown — previously the
    /// countdown existed only inside SOSView, so the SOS buttons on the
    /// journey, navigation and offline screens fired instantly with no chance
    /// to cancel, while the identical-looking button on Home did not.
    private(set) var sosCountdown: Int?
    private var sosCountdownTask: Task<Void, Never>?

    /// THE entry point for every user-facing SOS affordance.
    ///
    /// Always shows the SOS screen and starts a cancellable countdown, so the
    /// outcome of pressing "SOS" is identical no matter which screen it was
    /// pressed on. Do NOT call activateSOS/triggerSOS directly from a view for
    /// a user-initiated SOS — that path is for genuinely automatic triggers
    /// (Watch, fall, discreet phrase, journey timeout) which have already done
    /// their own confirmation and must not wait.
    func beginSOSCountdown(source: EmergencySource = .manual, message: String? = nil) {
        guard !emergency.isSOSActive else {
            showSOSScreen = true
            return
        }
        showSOSScreen = true
        pendingSOSSource = source
        pendingSOSMessage = message
        sosCountdown = Self.sosCountdownDuration
        Haptics.warning()
        sosCountdownTask?.cancel()
        sosCountdownTask = Task { [weak self] in
            for remaining in stride(from: Self.sosCountdownDuration - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self?.sosCountdown = remaining
                if remaining <= 3 { Haptics.tap() }
            }
            guard !Task.isCancelled, let self else { return }
            self.sosCountdown = nil
            self.sosCountdownTask = nil
            self.triggerSOS(source: self.pendingSOSSource, message: self.pendingSOSMessage)
        }
    }

    /// Cancel a countdown before it fires. Safe to call when none is running.
    func cancelSOSCountdown() {
        guard sosCountdownTask != nil else { return }
        sosCountdownTask?.cancel()
        sosCountdownTask = nil
        sosCountdown = nil
        emergencyNote = nil
        Haptics.success()
    }

    private var pendingSOSSource: EmergencySource = .manual
    private var pendingSOSMessage: String?

    @discardableResult
    func triggerSOS(source: EmergencySource, message: String? = nil) -> EmergencyPacket? {
        let msg: String
        switch source {
        case .medicalSOS:      msg = message ?? "Medical emergency. I need help."
        case .discreetPhrase:  msg = message ?? "I need help. This is a discreet SOS alert."
        case .gesture:         msg = message ?? "I need help. This is a silent SOS alert triggered by a phone gesture."
        case .actionButton:    msg = message ?? "I need help. This is a silent SOS alert triggered by the Action Button."
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

        guardianService.logExternalEvent(emergencyID: packet.packetID, label: "SOS activated")
        guardianService.startSearch(emergencyID: packet.packetID, category: source, coordinate: coord)

        // Audio evidence starts here, not in SOSView. It used to live in that
        // view's .task, which meant an SOS from the Watch, the Action Button or
        // any path where SOSView wasn't actually on screen recorded nothing —
        // the alert went out but the evidence silently didn't start.
        if emergency.microphonePermission == .granted, !emergency.isRecording {
            emergency.startEvidence(kind: .audio, location: coord,
                                    safetyState: .emergency, journeyID: nil,
                                    context: context)
        }

        // Fire-and-forget: Telegram alert + Omnidimension AI call run in background
        // so they never delay the emergency UI appearing. The handle is kept
        // so resolveSOS() can actually cancel it — URLSession requests are
        // cooperatively cancellable, so "I'm Safe Now" genuinely stops an
        // in-flight call/message rather than just dismissing the screen while
        // it silently continues to a contact after the user is already safe.
        let loc = location.currentLocation
        let senderName = sender
        // Captured BEFORE the Task, like senderName: the line below clears
        // emergencyNote synchronously, so reading it inside the Task body
        // raced with that clear and sent an empty note — the user's typed
        // description of what was happening never reached the alert.
        let note = emergencyNote ?? ""
        emergencyNote = nil
        alertTask?.cancel()
        alertTask = Task {
            await alerts.sendSOSAlert(location: loc, note: note, senderName: senderName)
        }

        return packet
    }

    /// Optional note typed by the user on the pre-activation countdown screen.
    /// Set before calling activateSOS; cleared after use.
    var emergencyNote: String? = nil

    /// The in-flight Telegram/Omnidimension alert Task from the most recent
    /// activateSOS — cancelled by resolveSOS() so marking safe actually stops
    /// any call/message still in flight.
    private var alertTask: Task<Void, Never>?

    func resolveSOS() {
        // Also stops a countdown that hasn't fired yet, so "I'm safe" works
        // whether the SOS is pending or already sent.
        cancelSOSCountdown()
        alertTask?.cancel()
        alertTask = nil
        if let emergencyID = emergency.currentPacket?.packetID {
            guardianService.endSearch(emergencyID: emergencyID)
        }
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
    //
    // Requires THREE detections within 30 seconds to trigger, reducing false
    // positives from the phrase appearing in normal conversation.

    private var discreetPhraseCount = 0
    private var firstDiscreetDetectionAt: Date?
    private let discreetDetectionWindow: TimeInterval = 30

    func startDiscreetListening(phrase: String, countdownSeconds: Int = 10) {
        discreetPhraseCount = 0
        firstDiscreetDetectionAt = nil
        voiceTrigger.startListening(phrase: phrase) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = Date.now
                // Reset if the detection window has expired
                if let first = self.firstDiscreetDetectionAt,
                   now.timeIntervalSince(first) > self.discreetDetectionWindow {
                    self.discreetPhraseCount = 0
                    self.firstDiscreetDetectionAt = nil
                }
                if self.discreetPhraseCount == 0 { self.firstDiscreetDetectionAt = now }
                self.discreetPhraseCount += 1
                Haptics.tap()   // subtle feedback so user knows each detection registered
                if self.discreetPhraseCount >= 3 {
                    self.discreetPhraseCount = 0
                    self.firstDiscreetDetectionAt = nil
                    self.beginDiscreetCountdown(seconds: countdownSeconds)
                }
            }
        }
    }

    /// The in-flight auto-arm request (permission check + startListening) —
    /// tracked so backgrounding mid-request can actually cancel it. Without
    /// this, a still-pending permission/auth await could resume and arm the
    /// mic right after stopDiscreetListening() was told to disarm it.
    private var autoArmTask: Task<Void, Never>?

    func stopDiscreetListening() {
        autoArmTask?.cancel()
        autoArmTask = nil
        voiceTrigger.stopListening()
    }

    /// Auto-arms Discreet SOS whenever the app is foregrounded, so the user
    /// never has to remember to tap "Start Listening" — matches the app's own
    /// enable/phrase settings, and requests microphone/speech authorization
    /// only if not already granted. Still foreground-only: iOS does not allow
    /// unrestricted background microphone access, so this must be re-armed
    /// (automatically, via scenePhase) every time the app returns to the
    /// foreground, and RootView disarms it the moment the app backgrounds.
    func autoArmDiscreetListeningIfEnabled(settings: DiscreetSOSSettings?) {
        guard let settings, settings.isEnabled,
              !settings.phrase.trimmingCharacters(in: .whitespaces).isEmpty,
              !voiceTrigger.isListening else { return }
        autoArmTask?.cancel()
        autoArmTask = Task {
            let granted = voiceTrigger.isAuthorized
                ? true
                : await voiceTrigger.requestAuthorization()
            guard !Task.isCancelled, granted else { return }
            startDiscreetListening(phrase: settings.phrase,
                                   countdownSeconds: settings.activationTimeoutSeconds)
        }
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

    // MARK: Gesture SOS (phone-side, no Watch needed)
    // Foreground-only: iOS suspends CoreMotion updates once the app leaves
    // the foreground, matching the same honest limitation as Discreet SOS.
    // Three sharp phone flicks within ~2 seconds starts a cancellable
    // countdown, exactly mirroring the Apple Watch app's gesture flow but
    // running directly on the phone — no Watch pairing required.

    func armGestureSOS() {
        guard !gestureTrigger.isArmed else { return }
        gestureTrigger.arm(onFlick: {
            Haptics.tap()
        }, onTripleFlick: { [weak self] in
            self?.beginGestureCountdown()
        })
    }

    func disarmGestureSOS() {
        gestureTrigger.disarm()
    }

    func beginGestureCountdown() {
        guard !gestureSOSPending else { return }
        gestureSOSPending = true
        gestureSOSCountdownSeconds = gestureSOSCountdownDuration
        gestureTrigger.pause() // don't let more flicks fire mid-countdown
        Haptics.warning()
        gestureCountdownTask?.cancel()
        gestureCountdownTask = Task { [weak self] in
            while let self, self.gestureSOSCountdownSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self.gestureSOSCountdownSeconds -= 1
            }
            guard let self, self.gestureSOSPending else { return }
            self.gestureSOSPending = false
            self.triggerSOS(source: .gesture)
        }
    }

    func cancelGestureSOS() {
        gestureCountdownTask?.cancel()
        gestureCountdownTask = nil
        gestureSOSPending = false
        Haptics.tap()
        if gestureTrigger.isArmed { gestureTrigger.resume() }
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

    /// Finds any EmergencyPacket the Action Button's background App Intent
    /// (TriggerSOSIntent) wrote directly to SwiftData and left .queued —
    /// that process has no AppModel/EmergencyService to call into, so it
    /// only persists the record. This is where that silent trigger actually
    /// completes: shows the SOS screen and adopts the packet into
    /// EmergencyService's active state, exactly as if it had just fired.
    /// Runs every time the app starts, so a queued trigger is never lost —
    /// only delayed until the app is next opened for any reason.
    private func completeQueuedBackgroundSOS(context: ModelContext) {
        let queuedActionButtonPackets = ((try? context.fetch(FetchDescriptor<EmergencyPacket>())) ?? [])
            .filter { $0.source == .actionButton && $0.deliveryState == .queued }
        guard let packet = queuedActionButtonPackets.max(by: { $0.timestamp < $1.timestamp }) else { return }

        emergency.adopt(queuedPacket: packet, mesh: mesh)
        showSOSScreen = true
        notifications.notify(.emergency, body: "A silent SOS from your Action Button is now active.")
        Haptics.emergency()
        recomputeSafety()
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
