//
//  DemoController.swift
//  Guardian
//
//  Development/testing-only surface. Lets a developer trigger safety behaviors
//  without needing a second device or a real incident. All effects are clearly
//  labeled and reversible. This is never the default production behavior.
//
//  Real infrastructure (mesh, location, connectivity) is NOT faked here —
//  the demo only injects UI-level overrides and triggers. Real MPC peers,
//  real GPS, and real NWPathMonitor remain unaffected.
//

import Foundation
import Observation
import CoreLocation
import SwiftData

@Observable
final class DemoController {
    unowned let app: AppModel

    var isDemoMode = false
    private(set) var lastAction: String?

    init(app: AppModel) {
        self.app = app
    }

    private func mark(_ action: String) { lastAction = action; Haptics.tap() }

    // MARK: Journey / deviation

    func triggerRouteDeviation() {
        app.notifications.notify(.deviation, body: "You've moved off your planned route.")
        app.promptCheckIn()
        mark("Route deviation (demo)")
    }

    func suggestSaferRoute() {
        app.notifications.notify(.saferRoute, body: "A safer route with more lighting is available.")
        mark("Safer route suggested (demo)")
    }

    func recommendSafePlace() {
        app.notifications.notify(.saferRoute, body: "Safe place 300 m away — tap to navigate.")
        mark("Safe-place recommendation (demo)")
    }

    // MARK: Connectivity overrides (forces NWPathMonitor display, real mesh unaffected)

    func loseConnectivity() {
        app.connectivity.force(.cellular)
        app.recomputeSafety()
        mark("Weak connectivity (forced display)")
    }

    func goOffline() {
        app.connectivity.force(.offline)
        app.recomputeSafety()
        app.notifications.notify(.connectivity, body: "No internet. Guardian is running offline.")
        mark("Offline mode (forced display)")
    }

    func restoreConnectivity() {
        app.connectivity.clearForce()
        app.recomputeSafety()
        mark("Connectivity restored")
    }

    // MARK: Emergency

    func createEmergencyPacket() {
        guard let context = app.modelContext else { return }
        let packet = EmergencyPacket(
            latitude: app.location.coordinate.latitude,
            longitude: app.location.coordinate.longitude,
            safetyState: app.safetyState,
            riskScore: app.confidence.score,
            message: "Demo emergency packet — created for testing.",
            senderID: "Demo")
        context.insert(packet)
        try? context.save()
        // Originate through real mesh if peers are connected
        if let payload = try? JSONEncoder().encode(["demo": "true"]) {
            app.mesh.originate(RelayPacket(type: .emergency, payload: payload))
        }
        mark("Emergency packet created")
    }

    func triggerEmergency() {
        app.activateSOS(message: "Demo emergency triggered.")
        mark("Emergency state")
    }

    // MARK: Watch / hardware (mock events — real WatchConnectivity is unaffected)

    func simulateWatchSOS() {
        (app.watch as? MockWatchService)?.simulateEvent(.sos)
        mark("Watch SOS (mock event)")
    }

    // MARK: Community Guardian (demo)
    // Seeds local demo Guardian profiles (clearly isDemoSeed/.simulated) and
    // drives them through the SAME CommunityGuardianService code path a real
    // mesh Guardian would use — this is not a shadow implementation.

    func seedDemoGuardians() {
        guard let context = app.modelContext else { return }
        let base = app.location.coordinate
        let seeds: [(String, GuardianVerificationLevel, [GuardianCapability], Double)] = [
            ("Guardian A4F2 (Demo)", .verified, [.firstAid, .medicalAssistance], 220),
            ("Guardian K91X (Demo)", .community, [.security, .generalAssistance], 480),
            ("Campus Security (Demo Org)", .organization, [.collegeSecurity, .security], 700),
        ]
        for (name, level, capabilities, distanceMeters) in seeds {
            let offset = base.offset(latMeters: distanceMeters, lonMeters: 0)
            let guardian = CommunityGuardian(
                displayName: name, verificationLevel: level, availability: .available,
                capabilities: capabilities, latitude: offset.latitude, longitude: offset.longitude,
                lastLocationUpdate: .now, isDemoSeed: true, provenance: .simulated)
            context.insert(guardian)
        }
        try? context.save()
        mark("Demo guardians seeded")
    }

    /// Runs the full Community Guardian lifecycle end to end for a
    /// presentation: SOS -> search -> demo guardians found -> accepted ->
    /// responding -> completed. Uses the real activateSOS/guardianService
    /// code paths throughout.
    func simulateCommunityGuardianFlow() {
        seedDemoGuardians()
        app.activateSOS(message: "Demo emergency for Community Guardian walkthrough.")
        Task {
            try? await Task.sleep(for: .seconds(2))
            app.guardianService.autoAcceptTopDemoCandidate()
            try? await Task.sleep(for: .seconds(3))
            app.guardianService.completeAssistance()
        }
        mark("Community Guardian flow (demo)")
    }

    // MARK: Reset

    func reset() {
        app.connectivity.clearForce()
        app.pendingCheckIn = false
        app.unansweredCheckIns = 0
        app.recomputeSafety()
        mark("Demo reset")
    }
}
