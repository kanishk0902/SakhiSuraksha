//
//  PhoneConnectivityService.swift
//  GuardianWatch Watch App
//
//  Watch-side counterpart to RealWatchService (iOS). Sends
//  ["event": WatchEventKind.rawValue] via WCSession — the exact message shape
//  RealWatchService.session(_:didReceiveMessage:) already parses. Falls back
//  to updateApplicationContext when the phone isn't currently reachable, so a
//  triggered SOS still arrives once the phone wakes its session (store-and-
//  forward at the WatchConnectivity layer, separate from Guardian's own mesh
//  store-and-forward).
//

import Foundation
import WatchConnectivity
import Observation

@Observable
final class PhoneConnectivityService: NSObject {

    private(set) var isReachable = false
    private(set) var isPhoneAppInstalled = false
    private(set) var lastSendFailed = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Send an event immediately if the phone is reachable, and always also
    /// persist it as the current application context so it's delivered even
    /// if the phone wasn't reachable at the moment of the gesture.
    func send(_ kind: WatchEventKind) {
        let message = ["event": kind.rawValue]
        lastSendFailed = false

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in self?.lastSendFailed = true }
            }
        }

        // Always update application context too — delivered when the phone's
        // session next activates, even if sendMessage above didn't land.
        try? WCSession.default.updateApplicationContext(message)
    }
}

extension PhoneConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                              activationDidCompleteWith state: WCSessionActivationState,
                              error: Error?) {
        Task { @MainActor [weak self] in
            self?.isReachable = session.isReachable
            #if os(watchOS)
            self?.isPhoneAppInstalled = session.isCompanionAppInstalled
            #endif
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.isReachable = session.isReachable }
    }
}
