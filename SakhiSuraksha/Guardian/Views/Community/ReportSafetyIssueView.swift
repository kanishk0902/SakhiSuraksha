//
//  ReportSafetyIssueView.swift
//  Guardian
//
//  Community safety reports are reports, not proof. Never uses "this person
//  is dangerous" language, and never claims cross-user aggregation since
//  Guardian's SwiftData store is local to this device only.
//

import SwiftUI
import SwiftData
import CoreLocation

struct ReportSafetyIssueView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: CommunityReportType?
    @State private var note: String = ""
    @State private var isAnonymous = true
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GuardianTheme.cardSpacing) {
                    GuardianCard {
                        Text("Community safety report — stored only on this device, not shared with other users. This is a report, not proof of any crime.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    OptionRowList(data: CommunityReportType.allCases) { type in
                        OptionRow(title: type.title, systemImage: type.symbol,
                                 tint: GuardianTheme.caution, isSelected: selectedType == type) {
                            selectedType = type
                            Haptics.tap()
                        }
                    }

                    GuardianCard {
                        VStack(alignment: .leading, spacing: 12) {
                            GuardianSectionHeader(title: "Details (optional)", systemImage: "text.alignleft")
                            TextField("Add a note", text: $note, axis: .vertical)
                                .lineLimit(2...4)
                            Toggle("Post anonymously", isOn: $isAnonymous)
                        }
                    }

                    PrimaryActionButton(title: didSubmit ? "Report Submitted" : "Submit Report",
                                        systemImage: didSubmit ? "checkmark.circle.fill" : "flag.fill",
                                        color: selectedType == nil ? .secondary : GuardianTheme.caution) {
                        submit()
                    }
                    .disabled(selectedType == nil || didSubmit)
                    .opacity(selectedType == nil ? 0.6 : 1)
                }
                .padding()
            }
            .navigationTitle("Report Safety Issue")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func submit() {
        guard let type = selectedType else { return }
        let coord = app.location.currentLocation?.coordinate ?? LocationService.fallbackCoordinate
        let report = CommunityReport(reportType: type,
                                     latitude: coord.latitude,
                                     longitude: coord.longitude,
                                     note: note,
                                     isAnonymous: isAnonymous)
        context.insert(report)
        try? context.save()
        didSubmit = true
        Haptics.success()
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            dismiss()
        }
    }
}
