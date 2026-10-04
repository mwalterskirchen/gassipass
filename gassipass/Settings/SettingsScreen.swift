//
//  SettingsScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import SwiftUI

/// The settings of the app, which the gear button on the home screen opens.
/// The home screen pushes it, because a sixth tab makes iOS hide tabs
/// behind "More". A change counts at once, so the screen has no Save button.
struct SettingsScreen: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Toggle("Vibrate for Collected Segments", isOn: $settings.vibratesForCollectedSegments)
            } footer: {
                Text("The phone vibrates during a walk when a segment becomes collected.")
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
    }
    .environment(AppSettings())
}
