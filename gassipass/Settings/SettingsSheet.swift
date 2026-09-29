//
//  SettingsSheet.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import SwiftUI

/// The settings of the app, which the gear button on the home screen opens.
/// It is a sheet and not a tab, because a sixth tab makes iOS hide tabs
/// behind "More". A change counts at once, so the sheet has no Save button.
struct SettingsSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                Section {
                    Toggle("Vibrate for Collected Segments", isOn: $settings.vibratesForCollectedSegments)
                } footer: {
                    Text("The phone vibrates during a walk when a segment becomes collected.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    SettingsSheet()
        .environment(AppSettings())
}
