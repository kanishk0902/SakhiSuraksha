//
//  ContentView.swift
//  Guardian
//
//  Root navigation: five primary tabs plus the global SOS cover and the
//  intelligent safety check-in sheet.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Query private var discreetSOSSettings: [DiscreetSOSSettings]
    @State private var selection: Tab = .home

    enum Tab: Hashable { case home, journey, connect, safety, settings }

    var body: some View {
        @Bindable var app = app

        TabView(selection: $selection) {
            HomeView(selection: $selection)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            JourneyTabView()
                .tabItem { Label("Journey", systemImage: "figure.walk") }
                .tag(Tab.journey)

            ConnectView()
                .tabItem { Label("Connect", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.connect)

            SafetyTabView()
                .tabItem { Label("Safety", systemImage: "map.fill") }
                .tag(Tab.safety)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(GuardianTheme.accent)
        .fullCover(isPresented: $app.showSOSScreen) {
            SOSView()
        }
        .sheet(isPresented: $app.pendingCheckIn) {
            CheckInSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $app.discreetSOSPending) {
            DiscreetSOSCountdownSheet()
                .presentationDetents([.medium])
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $app.gestureSOSPending) {
            GestureSOSCountdownSheet()
                .presentationDetents([.medium])
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $app.showSafeHavens) { SafeHavensView() }
        .sheet(isPresented: $app.showCommunityGuardianStatus) { CommunityGuardianStatusView() }
        .sheet(isPresented: $app.showGuardianDashboard) { GuardianDashboardView() }
        // Discreet SOS auto-arms whenever the app is foregrounded (no manual
        // "Start Listening" tap needed) and disarms the moment it isn't —
        // iOS does not allow microphone/speech recognition to run in the
        // background, so re-arming on every foreground transition is the
        // closest real equivalent to "always listening."
        .onAppear {
            if scenePhase == .active {
                app.autoArmDiscreetListeningIfEnabled(settings: discreetSOSSettings.first)
                if app.gestureSOSAutoArm { app.armGestureSOS() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.autoArmDiscreetListeningIfEnabled(settings: discreetSOSSettings.first)
                if app.gestureSOSAutoArm { app.armGestureSOS() }
            } else {
                app.stopDiscreetListening()
                app.disarmGestureSOS()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
