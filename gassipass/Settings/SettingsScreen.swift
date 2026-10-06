//
//  SettingsScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import CoreData
import SwiftUI

/// The settings of the app, which the gear button on the home screen opens.
/// The home screen pushes it, because a sixth tab makes iOS hide tabs
/// behind "More". A change counts at once, so the screen has no Save button.
struct SettingsScreen: View {
    @Environment(AppSettings.self) private var settings
    @FetchRequest(fetchRequest: Pack.all()) private var packs

    var body: some View {
        @Bindable var settings = settings
        List {
            if packs.isEmpty {
                Section("Pack") {
                    Text("Your pack starts when you add your first dog.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(packs) { pack in
                Section("Pack") {
                    PackNameField(pack: pack)
                    PackMemberRows(pack: pack)
                    InviteMemberButton(pack: pack)
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
/// when the member leaves the field. A name from another phone shows while
/// the member does not edit the field.
private struct PackNameField: View {
    @ObservedObject var pack: Pack

    @Environment(Packs.self) private var packs
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
        Task { [packs, pack] in
            try? await packs.updateShareTitle(of: pack)
        }
    }

    private func show(_ packName: String) {
        name = packName
        shownName = packName
    }
}

/// The members of a pack, from its share. A pack that was never shared
/// lists no members. The list loads again after each sync event, which
/// brings the members who accepted the invitation.
private struct PackMemberRows: View {
    @ObservedObject var pack: Pack

    @Environment(Packs.self) private var packs
    @State private var members: [PackMember] = []

    var body: some View {
        ForEach(Array(members.enumerated()), id: \.offset) { _, member in
            LabeledContent {
                if member.isPackOwner {
                    Text("Pack Owner")
                } else if !member.hasAccepted {
                    Text("Invited")
                }
            } label: {
                let name = member.fullName ?? PackMember.unknownName
                if member.isThisPerson {
                    Text("\(name) (You)")
                } else {
                    Text(name)
                }
            }
        }
        .task(id: pack.isShared) {
            load()
            for await _ in NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification) {
                load()
            }
        }
    }

    private func load() {
        members = (try? packs.members(of: pack)) ?? []
    }
}

/// The button that sends an invitation to the pack with the share sheet.
/// Only the pack owner sees it.
private struct InviteMemberButton: View {
    @ObservedObject var pack: Pack

    @Environment(Packs.self) private var packs

    var body: some View {
        if packs.isPackOwner(of: pack) {
            ShareLink(
                item: packs.invitation(to: pack),
                preview: SharePreview(packs.shownName(of: pack))
            ) {
                Label("Invite Member", systemImage: "person.badge.plus")
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
    }
    .environment(AppSettings())
    .environment(Packs.preview)
    .environment(\.managedObjectContext, .preview)
}
