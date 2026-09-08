//
//  DiscreetSOSSettingsView.swift
//  Guardian
//
//  Set up a custom emergency phrase. Detection only runs while Guardian is
//  open in the foreground and you've tapped "Start Listening" — iOS does not
//  allow unrestricted background microphone access. The phrase is matched as
//  exact text, not tone or emotion — Guardian never claims to detect distress
//  in your voice, only the words you chose.
//

import SwiftUI
import SwiftData

struct DiscreetSOSSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allSettings: [DiscreetSOSSettings]
    @Query(sort: \EmergencyContact.name) private var contacts: [EmergencyContact]

    @State private var phrase: String = ""
    @State private var confirmPhrase: String = ""
    @State private var isEnabled = false
    @State private var timeoutSeconds = 10
    @State private var autoShareLocation = true
    @State private var phraseMismatch = false
    @State private var isListening = false

    private var settings: DiscreetSOSSettings? { allSettings.first }

    var body: some View {
        Form {
            Section {
                Text("Choose a phrase only you would say naturally — like \u{201C}Mummy\u{201D} or \u{201C}I forgot my bag.\u{201D} When Guardian hears it while listening, it silently starts an SOS countdown you can cancel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Emergency Phrase") {
                TextField("Enter phrase", text: $phrase)
                    .autocorrectionDisabled()
                TextField("Confirm phrase", text: $confirmPhrase)
                    .autocorrectionDisabled()
                if phraseMismatch {
                    Text("Phrases don't match.").font(.caption).foregroundStyle(GuardianTheme.emergency)
                }
            }

            Section("Behavior") {
                Toggle("Enable Discreet SOS", isOn: $isEnabled)
                Stepper("Silent countdown: \(timeoutSeconds)s", value: $timeoutSeconds, in: 5...30)
                Toggle("Auto-share location when triggered", isOn: $autoShareLocation)
            }

            Section("Trusted Contacts") {
                if contacts.isEmpty {
                    Text("Add contacts in Emergency Contacts to notify them.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(contacts) { contact in
                        Text(contact.name)
                    }
                }
            }

            Section {
                Button {
                    toggleListening()
                } label: {
                    Label(isListening ? "Stop Listening" : "Start Listening",
                          systemImage: isListening ? "waveform.slash" : "waveform")
                }
                .disabled(!isEnabled || phrase.isEmpty)
                Text("Only works while Guardian is open in the foreground. Guardian cannot listen while the app is closed or in the background — this is an iOS platform limitation, not a bug.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
        }
        .navigationTitle("Discreet SOS")
        .inlineNavigationTitle()
        .onAppear(perform: load)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                app.stopDiscreetListening()
                isListening = false
            }
        }
        .onDisappear {
            app.stopDiscreetListening()
            isListening = false
        }
    }

    private func load() {
        guard let settings else { return }
        phrase = settings.phrase
        confirmPhrase = settings.phrase
        isEnabled = settings.isEnabled
        timeoutSeconds = settings.activationTimeoutSeconds
        autoShareLocation = settings.autoShareLocation
    }

    private func save() {
        guard phrase == confirmPhrase else {
            phraseMismatch = true
            return
        }
        phraseMismatch = false
        if let existing = settings {
            existing.isEnabled = isEnabled
            existing.phrase = phrase
            existing.activationTimeoutSeconds = timeoutSeconds
            existing.autoShareLocation = autoShareLocation
            existing.updatedAt = .now
        } else {
            let new = DiscreetSOSSettings(isEnabled: isEnabled, phrase: phrase,
                                          activationTimeoutSeconds: timeoutSeconds,
                                          autoShareLocation: autoShareLocation)
            context.insert(new)
        }
        try? context.save()
        Haptics.success()
    }

    private func toggleListening() {
        if isListening {
            app.stopDiscreetListening()
            isListening = false
        } else {
            Task {
                let granted = await app.voiceTrigger.requestAuthorization()
                guard granted else { return }
                app.startDiscreetListening(phrase: phrase, countdownSeconds: timeoutSeconds)
                isListening = true
            }
        }
    }
}
