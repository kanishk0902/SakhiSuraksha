//
//  OnboardingView.swift
//  Guardian
//
//  First-launch walkthrough. Explains exactly what Guardian does at each step,
//  requests permissions in context so users know why, and previews the real SOS
//  SMS before they ever need it.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("guardian.onboardingComplete") private var complete = false
    @State private var page = 0

    private let totalPages = 7

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                contactsPage.tag(1)
                locationPage.tag(2)
                notificationsPage.tag(3)
                sosPage.tag(4)
                journeyPage.tag(5)
                donePage.tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            navBar
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        OnboardingPage(
            icon: "shield.fill",
            iconColor: GuardianTheme.accent,
            title: "Guardian",
            description: "Your personal safety companion. Guardian tracks your journey, alerts your contacts, and communicates — even when the internet is down.",
            extra: nil
        )
    }

    private var contactsPage: some View {
        OnboardingPage(
            icon: "person.2.fill",
            iconColor: GuardianTheme.safe,
            title: "Your Safety Network",
            description: "Add trusted people — family or friends — who should know if you're in danger. When you trigger SOS, Guardian opens an SMS pre-filled with your GPS location addressed to all of them.",
            extra: AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    Text("Example SMS Guardian will compose:").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("🚨 EMERGENCY from Priya")
                            .font(.caption.weight(.bold))
                        Text("I need help. My location:")
                            .font(.caption)
                        Text("maps.google.com/?q=28.6315,77.2167")
                            .font(.caption).foregroundStyle(GuardianTheme.accent)
                        Text("Call me or dial 112.")
                            .font(.caption)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                    Text("Add contacts after setup: Settings → Emergency Contacts")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            )
        )
    }

    private var locationPage: some View {
        OnboardingPage(
            icon: "location.fill",
            iconColor: GuardianTheme.accent,
            title: "Your Location",
            description: "Guardian uses GPS to track your journey and include your exact coordinates in emergency alerts. Your location is never shared without your action.",
            extra: AnyView(
                VStack(spacing: 10) {
                    Button {
                        app.location.requestPermission()
                        withAnimation { page += 1 }
                    } label: {
                        Label("Allow Location Access", systemImage: "location.fill")
                            .frame(maxWidth: .infinity).padding()
                            .background(GuardianTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white).font(.headline)
                    }
                    Text("You can change this anytime in iOS Settings")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            )
        )
    }

    private var notificationsPage: some View {
        OnboardingPage(
            icon: "bell.badge.fill",
            iconColor: GuardianTheme.caution,
            title: "Stay Informed",
            description: "Get notified if your route changes significantly, a check-in is missed, or an emergency alert has been relayed through nearby devices.",
            extra: AnyView(
                VStack(spacing: 10) {
                    Button {
                        Task {
                            await app.notifications.requestPermission()
                            withAnimation { page += 1 }
                        }
                    } label: {
                        Label("Enable Notifications", systemImage: "bell.fill")
                            .frame(maxWidth: .infinity).padding()
                            .background(GuardianTheme.caution, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white).font(.headline)
                    }
                    Text("Recommended — route deviation alerts need this")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            )
        )
    }

    private var sosPage: some View {
        OnboardingPage(
            icon: "sos",
            iconColor: GuardianTheme.emergency,
            title: "One-Touch Emergency",
            description: "Hold the SOS button for 1.2 seconds to activate. Guardian will:\n\n① Create a timestamped emergency packet with your location\n② Open an SMS to your contacts — you tap Send\n③ Relay the packet via nearby devices if you're offline\n\nYou are always in control. Guardian never calls or messages anyone automatically.",
            extra: nil
        )
    }

    private var journeyPage: some View {
        OnboardingPage(
            icon: "figure.walk.circle.fill",
            iconColor: GuardianTheme.accent,
            title: "Journey Tracking",
            description: "Enter your destination to start a journey. Guardian fetches a real walking route, then checks your GPS every 3 seconds.\n\nIf you deviate from the route for 3 readings in a row, you get a check-in prompt: \"Are you safe?\"\n\nIf you don't respond, the safety alert level rises — and your contacts may be notified.",
            extra: AnyView(
                HStack(spacing: 16) {
                    statusPill("On route", "checkmark.circle.fill", GuardianTheme.safe)
                    statusPill("Deviated", "exclamationmark.triangle.fill", GuardianTheme.caution)
                    statusPill("Alert", "sos", GuardianTheme.emergency)
                }
            )
        )
    }

    private var donePage: some View {
        OnboardingPage(
            icon: "checkmark.shield.fill",
            iconColor: GuardianTheme.safe,
            title: "You're Ready",
            description: "Guardian is set up and running.\n\nStart by going to Settings → Emergency Contacts to add the people who should hear from you in an emergency.\n\nThen try a journey — enter any destination and let Guardian watch over you.",
            extra: nil
        )
    }

    private func statusPill(_ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Navigation bar

    private var navBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<totalPages, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? GuardianTheme.accent : Color.secondary.opacity(0.25))
                        .frame(width: i == page ? 22 : 7, height: 7)
                        .animation(.spring(duration: 0.3), value: page)
                }
            }

            HStack {
                if page > 0 {
                    Button("Back") { withAnimation { page -= 1 } }
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if page < totalPages - 1 {
                    let isPermissionPage = page == 2 || page == 3
                    Button(isPermissionPage ? "Skip" : "Next") {
                        withAnimation { page += 1 }
                    }
                    .fontWeight(isPermissionPage ? .regular : .semibold)
                    .foregroundStyle(isPermissionPage ? .secondary : GuardianTheme.accent)
                } else {
                    Button {
                        complete = true
                    } label: {
                        Text("Get Started")
                            .font(.headline).foregroundStyle(.white)
                            .padding(.horizontal, 32).padding(.vertical, 13)
                            .background(GuardianTheme.accent, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 28)
        }
        .padding(.top, 14)
        .padding(.bottom, 40)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Reusable page layout

private struct OnboardingPage: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let extra: AnyView?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                Spacer(minLength: 60)

                Image(systemName: icon)
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .padding(.top, 40)

                VStack(spacing: 14) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)

                if let extra {
                    extra.padding(.top, 4)
                }

                Spacer(minLength: 140)
            }
            .padding(.horizontal, 28)
        }
    }
}
