//
//  SettingsScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import SwiftData
import SwiftUI

/// The settings of the app, which the gear button on the home screen opens.
/// The home screen pushes it, because a sixth tab makes iOS hide tabs
/// behind "More". A change counts at once, so the screen has no Save button.
struct SettingsScreen: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Account.self) private var account
    @Query(Pack.all()) private var packs: [Pack]

    var body: some View {
        @Bindable var settings = settings
        List {
            AccountSection()
            if packs.isEmpty {
                Section("Pack") {
                    Text("Your pack starts when you add your first dog.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(packs) { pack in
                Section {
                    PackNameField(pack: pack)
                    NavigationLink {
                        HomeBaseScreen(pack: pack, start: pack.homeBase)
                    } label: {
                        LabeledContent("Home Base", value: pack.homeBase == nil
                            ? String(localized: "Not set") : String(localized: "Set"))
                    }
                    PackMemberRows(pack: pack)
                } header: {
                    Text("Pack")
                } footer: {
                    if account.isPackOwner {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("An invitation is a link for one person. It works once and expires after 7 days.")
                            if account.packMembers.count > 1 {
                                Text("To remove a member, swipe their row to the left.")
                            }
                        }
                    }
                }
            }
            Section {
                Toggle("Vibrate for Collected Segments", isOn: $settings.vibratesForCollectedSegments)
            } footer: {
                Text("The phone vibrates during a walk when a segment becomes collected.")
            }
        }
        .navigationTitle("Settings")
        // The new members of the pack show after a refresh.
        .refreshesPack()
    }
}

/// The name of a pack, which every member can change. The account uploads
/// the new name after the save.
private struct PackNameField: View {
    let pack: Pack

    @Environment(Packs.self) private var packs

    var body: some View {
        NameField("Pack Name", prompt: Text(pack.shownName), name: pack.name) { name in
            try? packs.rename(pack, to: name)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
    }
    .environment(AppSettings())
    .environment(Packs.preview)
    .environment(Account.preview)
    .modelContainer(.preview)
}
