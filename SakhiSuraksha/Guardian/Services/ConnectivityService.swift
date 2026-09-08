//
//  ConnectivityService.swift
//  Guardian
//
//  Reports the real network path (via NWPathMonitor) and models Guardian's
//  communication hierarchy: internet → cellular → peer/mesh → offline store.
//  Demo mode can override the state to showcase offline / mesh behavior.
//

import Foundation
import Network
import Observation

@Observable
final class ConnectivityService {

    private(set) var state: ConnectivityState = .online
    /// When true, the state is being forced by demo mode rather than the OS.
    private(set) var isForced: Bool = false

    /// Called on the main actor whenever the real network path changes.
    var onStateChange: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "guardian.connectivity")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let resolved: ConnectivityState
            if path.status == .satisfied {
                resolved = path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi)
                    ? .cellular : .online
            } else {
                resolved = .offline
            }
            Task { @MainActor in
                guard !self.isForced else { return }
                let changed = self.state != resolved
                self.state = resolved
                if changed { self.onStateChange?() }
            }
        }
        monitor.start(queue: queue)
    }

    // MARK: Demo overrides

    func force(_ state: ConnectivityState) {
        isForced = true
        self.state = state
    }

    func clearForce() {
        isForced = false
    }

    // MARK: Derived

    var canReachContacts: Bool { state.hasInternet }

    var explanation: String {
        switch state {
        case .online:   return "Connected to the internet. Live sharing and calls are available."
        case .cellular: return "Cellular data available. Messaging and location sharing work."
        case .offline:  return "No internet. Guardian keeps working locally and via nearby mesh."
        case .mesh:     return "Relaying through nearby Guardian devices toward an internet gateway."
        }
    }
}
