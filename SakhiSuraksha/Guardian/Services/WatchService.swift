//
//  WatchService.swift
//  Guardian
//
//  Real WatchConnectivity integration (phone side). RealWatchService activates
//  WCSession and reports true pairing/reachability state. The companion Watch
//  app sends events using the message format: ["event": WatchSafetyEvent.Kind.rawValue].
//
//  On non-iOS platforms, or when no Watch is paired, MockWatchService is used
//  and the UI correctly shows "Apple Watch not connected".
//

import Foundation
import Observation

// MARK: - Protocol

protocol WatchService: AnyObject {
    var isPaired: Bool { get }
    var isReachable: Bool { get }
    var statusDescription: String { get }
    func onEvent(_ handler: @escaping (WatchSafetyEvent) -> Void)
}

// MARK: - Real implementation (iOS + paired Watch)

#if os(iOS)
import WatchConnectivity

@Observable
final class RealWatchService: NSObject, WatchService {

    private(set) var isPaired = false
    private(set) var isReachable = false
    private(set) var isWatchAppInstalled = false
    private var eventHandler: ((WatchSafetyEvent) -> Void)?

    var statusDescription: String {
        guard WCSession.isSupported() else { return "Apple Watch not supported on this device" }
        guard isPaired                else { return "Apple Watch not paired" }
        guard isWatchAppInstalled     else { return "Guardian Watch app not installed" }
        return isReachable ? "Apple Watch connected" : "Apple Watch paired but not in range"
    }

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func onEvent(_ handler: @escaping (WatchSafetyEvent) -> Void) {
        self.eventHandler = handler
    }
}

// MARK: WCSessionDelegate

extension RealWatchService: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                              activationDidCompleteWith state: WCSessionActivationState,
                              error: Error?) {
        Task { @MainActor [weak self] in
            self?.isPaired = session.isPaired
            self?.isWatchAppInstalled = session.isWatchAppInstalled
            self?.isReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.isReachable = false }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.isReachable = false
            WCSession.default.activate()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.isReachable = session.isReachable }
    }

    /// Receive safety events sent by the Watch companion app.
    nonisolated func session(_ session: WCSession,
                              didReceiveMessage message: [String: Any]) {
        guard let kindStr = message["event"] as? String,
              let kind = WatchSafetyEvent.Kind(rawValue: kindStr) else { return }
        let event = WatchSafetyEvent(kind: kind)
        Task { @MainActor [weak self] in self?.eventHandler?(event) }
    }

    /// Receive safety events sent while Watch was not reachable.
    nonisolated func session(_ session: WCSession,
                              didReceiveApplicationContext applicationContext: [String: Any]) {
        if let kindStr = applicationContext["event"] as? String,
           let kind = WatchSafetyEvent.Kind(rawValue: kindStr) {
            let event = WatchSafetyEvent(kind: kind)
            Task { @MainActor [weak self] in self?.eventHandler?(event) }
        }
    }
}
#endif

// MARK: - Fallback mock (macOS / no Watch / dev/demo)

@Observable
final class MockWatchService: WatchService {
    private(set) var isPaired = false
    private(set) var isReachable = false
    private var eventHandler: ((WatchSafetyEvent) -> Void)?

    var statusDescription: String { "Apple Watch not connected" }

    func onEvent(_ handler: @escaping (WatchSafetyEvent) -> Void) {
        self.eventHandler = handler
    }

    // Development/demo only — not on the WatchService protocol.
    func simulateEvent(_ kind: WatchSafetyEvent.Kind) {
        eventHandler?(WatchSafetyEvent(kind: kind))
    }
}
