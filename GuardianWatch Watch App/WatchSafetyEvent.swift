//
//  WatchSafetyEvent.swift
//  GuardianWatch Watch App
//
//  Mirrors the message contract already defined on the iPhone side in
//  Guardian/Models/ValueModels.swift (WatchSafetyEvent) and consumed by
//  RealWatchService in Guardian/Services/WatchService.swift. The two targets
//  can't share source directly (the iOS file pulls in iOS-only imports), so
//  this is a deliberate, minimal duplicate of just the wire contract:
//  a message dictionary shaped ["event": Kind.rawValue]. Keep the case list
//  identical to the iPhone app's WatchSafetyEvent.Kind if you add cases there.
//

import Foundation

enum WatchEventKind: String {
    case sos, checkIn, fall, heartRateSpike, journeyState
}
