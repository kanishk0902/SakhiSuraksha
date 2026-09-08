//
//  EvidenceView.swift
//  Guardian
//
//  Explicit, user-controlled evidence capture. Guardian NEVER records silently —
//  a capture always has a visible indicator and an explicit start. Only metadata
//  is stored locally; a future upload/relay abstraction is stubbed.
//

import SwiftUI
import SwiftData
import CoreLocation

struct EvidenceView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EmergencyEvidence.startedAt, order: .reverse) private var records: [EmergencyEvidence]

    @State private var kind: EvidenceKind = .audio

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GuardianTheme.cardSpacing) {
                    privacyBanner
                    captureCard
                    if !records.isEmpty { historyCard }
                }
                .padding()
            }
            .navigationTitle("Emergency Evidence")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .guardianTrailing) {
                    Button("Done") {
                        if app.emergency.isRecording {
                            app.emergency.stopEvidence(context: context)
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    private var privacyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
            Text("Guardian never records silently. Recording is always started by you and clearly indicated.")
                .font(.caption)
            Spacer()
        }
        .padding(12)
        .background(GuardianTheme.safe.opacity(0.14))
        .foregroundStyle(GuardianTheme.safe)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var captureCard: some View {
        GuardianCard {
            VStack(spacing: 16) {
                if app.emergency.isRecording {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack(spacing: 8) {
                            Circle().fill(GuardianTheme.emergency).frame(width: 12, height: 12)
                                .opacity(0.9)
                                .overlay(Circle().stroke(GuardianTheme.emergency, lineWidth: 2)
                                    .scaleEffect(1.6).opacity(0.4))
                            Text("RECORDING \(app.emergency.recordingKind?.rawValue.uppercased() ?? "")")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(GuardianTheme.emergency)
                            Spacer()
                            Text(timeString(currentElapsed))
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                } else {
                    Picker("Type", selection: $kind) {
                        Label("Audio", systemImage: "waveform").tag(EvidenceKind.audio)
                        Label("Video", systemImage: "video.fill").tag(EvidenceKind.video)
                        Label("Photo", systemImage: "camera.fill").tag(EvidenceKind.photo)
                    }
                    .pickerStyle(.segmented)
                }

                Button {
                    toggleRecording()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: app.emergency.isRecording ? "stop.fill" : "record.circle")
                        Text(app.emergency.isRecording ? "Stop Recording" : "Start Recording")
                            .font(.headline)
                    }
                    .guardianCapsule(app.emergency.isRecording ? GuardianTheme.alert : GuardianTheme.emergency)
                }
                .buttonStyle(PressableStyle())

                Text("Captured with timestamp, location, journey and safety state. Metadata is stored locally and can be relayed later.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var historyCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: 12) {
                GuardianSectionHeader(title: "Stored Evidence", systemImage: "externaldrive.fill")
                ForEach(records) { record in
                    HStack {
                        Image(systemName: record.kind.symbol)
                            .foregroundStyle(GuardianTheme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.kind.rawValue.capitalized)
                                .font(.subheadline.weight(.semibold))
                            Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(timeString(record.durationSeconds))
                                .font(.caption.monospacedDigit())
                            Text(record.uploaded ? "Uploaded" : "Local only")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if record.evidenceID != records.last?.evidenceID { Divider() }
                }
            }
        }
    }

    private var currentElapsed: TimeInterval {
        guard let started = app.emergency.recordingStartedAt else { return 0 }
        return Date.now.timeIntervalSince(started)
    }

    private func toggleRecording() {
        if app.emergency.isRecording {
            app.emergency.stopEvidence(context: context)
            Haptics.tap()
        } else {
            guard let coord = app.location.currentLocation?.coordinate else { return }
            app.emergency.startEvidence(kind: kind,
                                        location: coord,
                                        safetyState: app.safetyState,
                                        journeyID: app.journey.active?.id,
                                        context: context)
            Haptics.warning()
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
