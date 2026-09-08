//
//  GuardianWatchApp.swift
//  GuardianWatch Watch App
//

import SwiftUI

@main
struct GuardianWatch_Watch_AppApp: App {
    @State private var connectivity = PhoneConnectivityService()
    @State private var gesture = GestureTriggerService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connectivity)
                .environment(gesture)
        }
    }
}
