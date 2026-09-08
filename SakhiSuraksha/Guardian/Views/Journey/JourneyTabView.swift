//
//  JourneyTabView.swift
//  Guardian
//
//  Shows the journey setup when idle, or the live journey when one is active.
//

import SwiftUI

struct JourneyTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                if app.journey.isActive {
                    ActiveJourneyView()
                } else {
                    JourneySetupView()
                }
            }
            .navigationTitle("Journey")
        }
    }
}
