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
                Section("Pack") {
                    PackNameField(pack: pack)
                }
            }
            Section {
                Toggle("Vibrate for Collected Segments", isOn: $settings.vibratesForCollectedSegments)
            } footer: {
                Text("The phone vibrates during a walk when a segment becomes collected.")
            }
        }
        .navigationTitle("Settings")
    }
}

/// The name of a pack, which every member can change. The new name counts
/// when the member leaves the field.
private struct PackNameField: View {
    let pack: Pack

    @Environment(Packs.self) private var packs
    @Environment(Account.self) private var account
    @State private var name: String
    /// The name of the pack when the field last showed it, so that only an
    /// edit in the field renames the pack.
    @State private var shownName: String
    @FocusState private var isFocused: Bool

    init(pack: Pack) {
        self.pack = pack
        _name = State(initialValue: pack.name)
        _shownName = State(initialValue: pack.name)
    }

    var body: some View {
        TextField("Pack Name", text: $name, prompt: Text(packs.shownName(of: pack)))
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .focused($isFocused)
            .onChange(of: isFocused) {
                if !isFocused {
                    save()
                }
            }
            .onChange(of: pack.name) {
                if !isFocused {
                    show(pack.name)
                }
            }
            .onDisappear(perform: save)
    }

    private func save() {
        guard name != shownName else { return }
        try? packs.rename(pack, to: name)
        show(pack.name)
        Task {
            await account.upload()
        }
    }

    private func show(_ packName: String) {
        name = packName
        shownName = packName
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
