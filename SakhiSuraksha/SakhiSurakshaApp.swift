//
//  SakhiSurakshaApp.swift
//  Guardian
//
//  App entry point. Sets up the SwiftData container and the shared AppModel.
//

import SwiftUI
import SwiftData
import UIKit
import CoreLocation

@main
struct SakhiSurakshaApp: App {

    let container: ModelContainer = {
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
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memory])
        }
    }()

    @State private var appModel = AppModel()

    @AppStorage("guardian.onboardingComplete") private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingComplete {
                    RootView()
                } else {
                    OnboardingView()
                }
            }
            .environment(appModel)
            .onAppear {
                appModel.start(context: container.mainContext)
            }
        }
        .modelContainer(container)
    }
}
