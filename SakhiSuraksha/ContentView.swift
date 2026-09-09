//
//  ContentView.swift
//  Guardian
//
//  Root navigation: five primary tabs plus the global SOS cover and the
//  intelligent safety check-in sheet.
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
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
        .sheet(isPresented: $app.showMedicalSOS) { MedicalSOSView() }
        .sheet(isPresented: $app.showPeriodEmergency) { PeriodEmergencyView() }
        .sheet(isPresented: $app.showINeedHelp) { INeedHelpView() }
        .sheet(isPresented: $app.showSafeHavens) { SafeHavensView() }
        .sheet(isPresented: $app.showWomenSupport) { WomenSupportView() }
        .sheet(isPresented: $app.showReportSafetyIssue) { ReportSafetyIssueView() }
        .sheet(isPresented: $app.showSafetyReports) { SafetyReportsView() }
        .sheet(isPresented: $app.showCommunityGuardianStatus) { CommunityGuardianStatusView() }
        .sheet(isPresented: $app.showBecomeGuardian) { BecomeGuardianView() }
        .sheet(isPresented: $app.showGuardianDashboard) { GuardianDashboardView() }
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
