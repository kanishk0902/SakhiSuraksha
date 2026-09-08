//
//  DemoPanelView.swift
//  Guardian
//
//  Demo mode has been removed. This file is kept to avoid broken references
//  during the transition — it can be deleted once SettingsView no longer
//  references it (it already doesn't after the last edit).
//

import SwiftUI

struct DemoPanelView: View {
    var body: some View {
        ContentUnavailableView("Demo mode removed",
                               systemImage: "wand.and.stars.inverse",
                               description: Text("All data is now live."))
            .navigationTitle("Demo Mode")
    }
}
