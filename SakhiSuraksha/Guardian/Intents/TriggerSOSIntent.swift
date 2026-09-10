//
//  TriggerSOSIntent.swift
//  Guardian
//
//  App Intent for the iPhone Action Button (15 Pro/16 series): assign this
//  shortcut to the Action Button in iOS Settings → Action Button → Shortcut.
//  Runs fully in the background — no Guardian UI opens, no Messages compose
//  screen appears. This is a deliberate product choice: in some real threat
//  scenarios, the phone screen lighting up is itself dangerous, so silence
//  was chosen over guaranteed real-time contact notification.
//
//  IMPORTANT TRADEOFF (documented, not hidden): because this never shows any
//  UI, it cannot use the sms: URL scheme (Apple requires the Messages
//  compose UI to appear for that — no exceptions). So trusted contacts are
//  NOT notified in real time by this trigger alone. It creates a fully real,
//  persisted EmergencyPacket with best-effort location — the same record
//  every other SOS source creates — marked .queued. The next time Guardian
//  is opened for ANY reason, AppModel.completeQueuedBackgroundSOS() detects
//  it and finishes the flow (composes the SMS, starts the timeline, shows
//  the SOS screen) automatically, so nothing is lost — just delayed until
//  the app is next opened.
//
//  Runs in-process if Guardian is already running, or in a short-lived
//  background extension process otherwise — either way this does NOT touch
//  AppModel (which may not exist yet in that process). It opens the same
//  on-disk SwiftData store directly, exactly like AppModel does at launch.
//

import AppIntents
import SwiftData
import CoreLocation

struct TriggerSOSIntent: AppIntent {
    static var title: LocalizedStringResource = "Guardian SOS"
    static var description = IntentDescription("Silently records an emergency alert with your location. No screen opens. Trusted contacts are notified the next time Guardian is opened.")

    /// Background execution — never brings Guardian's UI to the foreground.
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let coordinate = await Self.bestEffortLocation()
        Self.writeQueuedPacket(coordinate: coordinate)
        return .result()
    }

    // MARK: Location

    /// A short, bounded best-effort location fetch. Background App Intents
    /// get a limited execution window, so this never blocks indefinitely —
    /// falls back to a sentinel "unknown" coordinate rather than failing the
    /// whole intent if a fix can't be obtained in time.
    private static func bestEffortLocation() async -> CLLocationCoordinate2D {
        await withCheckedContinuation { continuation in
            let fetcher = OneShotLocationFetcher()
            fetcher.fetch(timeout: 4) { coordinate in
                continuation.resume(returning: coordinate ?? LocationService.fallbackCoordinate)
            }
        }
    }

    // MARK: Persistence

    /// Opens the same on-disk SwiftData store AppModel uses (same schema,
    /// same default ModelConfiguration) and writes a queued EmergencyPacket
    /// directly — this process may not have (or may not yet have) a running
    /// AppModel to call into.
    private static func writeQueuedPacket(coordinate: CLLocationCoordinate2D) {
        let schema = Schema([
            UserProfile.self,
            EmergencyContact.self,
            EmergencyPacket.self,
            EmergencyEvidence.self,
            JourneyRecord.self,
            PersistedRelayPacket.self,
            MedicalSOSEvent.self,
            CommunityReport.self,
            DiscreetSOSSettings.self,
            CommunityGuardian.self,
            CommunityGuardianRequest.self,
            EmergencyTimelineEvent.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else { return }
        let context = ModelContext(container)

        let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first
        let sender = (profile?.name.isEmpty == false ? profile!.name : "Guardian User")
        let message = profile?.emergencyMessage
            ?? "I need help. This is a silent SOS alert triggered by the Action Button."

        let packet = EmergencyPacket(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            safetyState: .emergency,
            riskScore: 0, // unknown outside AppModel's live SafetyEngine context
            message: message,
            senderID: sender,
            deliveryState: .queued,
            source: .actionButton)
        context.insert(packet)
        try? context.save()
    }
}

/// Minimal one-shot CLLocationManager wrapper for use outside AppModel's
/// LocationService (which assumes a long-lived, already-authorized
/// foreground app). If permission was never granted, this returns nil
/// quickly rather than hanging — the Action Button intent still records a
/// real emergency packet with a fallback coordinate rather than failing
/// silently with nothing recorded at all.
private final class OneShotLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((CLLocationCoordinate2D?) -> Void)?
    private var didComplete = false

    func fetch(timeout: TimeInterval, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.completion = completion
        manager.delegate = self

        guard manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse else {
            finish(with: nil)
            return
        }

        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestLocation()

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(with: nil)
        }
    }

    private func finish(with coordinate: CLLocationCoordinate2D?) {
        guard !didComplete else { return }
        didComplete = true
        completion?(coordinate)
        completion = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(with: locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }
}
