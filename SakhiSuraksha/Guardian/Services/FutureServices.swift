//
//  FutureServices.swift
//  Guardian
//
//  Protocols and stub implementations for future hardware integrations:
//  discreet companion hardware (muscle-sensor band, keyfob) and CCTV/anomaly
//  data feeds. Both currently return no data — the protocols define the
//  interfaces for when real backends are available.
//
//  WatchService has been moved to WatchService.swift (real WCSession implementation).
//

import Foundation
import Observation

// MARK: - Companion hardware (future)

/// Future discreet hardware that can trigger an SOS without touching the phone
/// (e.g. a muscle-sensor band, smart keyfob). Not wired to real hardware yet.
protocol HardwareService: AnyObject {
    var isConnected: Bool { get }
    func onEvent(_ handler: @escaping (HardwareSafetyEvent) -> Void)
}

@Observable
final class MockHardwareService: HardwareService {
    private(set) var isConnected = false
    private var handler: ((HardwareSafetyEvent) -> Void)?

    func onEvent(_ handler: @escaping (HardwareSafetyEvent) -> Void) {
        self.handler = handler
    }

    // Development/demo only.
    func simulateEvent(_ eventType: HardwareSafetyEvent.EventKind, confidence: Double = 0.9) {
        handler?(HardwareSafetyEvent(source: .muscleSensor,
                                     eventType: eventType, confidence: confidence))
    }
}

// MARK: - CCTV / anomaly feed (future)

/// Future CCTV coverage and anomaly data provider. Returns zero coverage until
/// a real backend (e.g. a CV server) is integrated.
protocol CCTVService: AnyObject {
    /// Average coverage in the current area, 0...100. 0 = no data.
    var averageCoverage: Int { get }
    var anomalyActive: Bool { get }
}

@Observable
final class MockCCTVService: CCTVService {
    var averageCoverage: Int = 0    // 0 = no real data source connected
    var anomalyActive: Bool = false
}
