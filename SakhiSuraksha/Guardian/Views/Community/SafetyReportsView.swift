//
//  SafetyReportsView.swift
//  Guardian
//
//  Your own community safety reports — stored only on this device. Guardian
//  has no backend to sync or aggregate reports across users, so this never
//  claims to show anyone else's reports or a crime prediction.
//

import SwiftUI
import SwiftData
import CoreLocation

struct SafetyReportsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CommunityReport.createdAt, order: .reverse) private var reports: [CommunityReport]
    @State private var showReportSheet = false
    @State private var showMap = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $showMap) {
                    Text("Map").tag(true)
                    Text("List").tag(false)
                }
                .pickerStyle(.segmented)
                .padding()

                if showMap {
                    GuardianMap(communityReports: reports,
                               destination: nil)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    list
                }
            }
            .navigationTitle("Safety Reports")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .guardianTrailing) {
                    Button {
                        showReportSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Report a safety issue")
                }
            }
            .sheet(isPresented: $showReportSheet) { ReportSafetyIssueView() }
        }
    }

    private var list: some View {
        List {
            Section {
                Text("Your reports, stored only on this device — not shared with other users.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if reports.isEmpty {
                Section {
                    Text("No reports yet. Tap + to report a safety concern.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(reports) { report in
                        HStack(spacing: 12) {
                            Image(systemName: report.reportType.symbol)
                                .foregroundStyle(GuardianTheme.caution)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.reportType.title).font(.subheadline.weight(.semibold))
                                if !report.note.isEmpty {
                                    Text(report.note).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(reports[index]) }
        try? context.save()
    }
}
