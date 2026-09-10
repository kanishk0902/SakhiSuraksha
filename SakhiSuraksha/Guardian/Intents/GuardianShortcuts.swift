//
//  GuardianShortcuts.swift
//  Guardian
//
//  Exposes TriggerSOSIntent as an assignable Shortcut — needed for it to
//  appear in iOS Settings → Action Button → Shortcut, and in the Shortcuts
//  app generally.
//

import AppIntents

struct GuardianShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TriggerSOSIntent(),
            phrases: ["Send \(.applicationName) SOS", "\(.applicationName) emergency"],
            shortTitle: "Guardian SOS",
            systemImageName: "sos"
        )
    }
}
