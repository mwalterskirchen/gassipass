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
                    LeavePackButton(pack: pack)
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
        // The pack is gone when this person left it or the pack owner
        // removed them while the field was open.
        guard name != shownName, !pack.isDeleted, pack.managedObjectContext != nil else { return }
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
/// lists no members. The rows render again after each sync event, which
/// brings the members who accepted the invitation, because
/// `Packs.members(of:)` observes the sync events.
private struct PackMemberRows: View {
    @ObservedObject var pack: Pack

    @Environment(Packs.self) private var packs

    var body: some View {
        // Read in the body and not in a task: a modifier on an empty
        // `ForEach` never runs, so a task would never load the first member.
        let members = (try? packs.members(of: pack)) ?? []
        ForEach(members) { member in
            PackMemberRow(member: member, pack: pack)
        }
    }
}

/// A member of a pack, with their role or whether they have accepted the
/// invitation. The pack owner removes the member with a swipe or the
/// context menu of the row.
private struct PackMemberRow: View {
    let member: PackMember
    let pack: Pack

    @Environment(Packs.self) private var packs
    @State private var isConfirmingRemoval = false
    @State private var removalFailed = false

    var body: some View {
        memberLabel
            .swipeActions {
                if packs.mayRemove(member, from: pack) {
                    // Without the destructive role, because with it the list
                    // removes the row before the question is answered.
                    Button("Remove", systemImage: "person.badge.minus") { isConfirmingRemoval = true }
                        .tint(.red)
                }
            }
            .contextMenu {
                if packs.mayRemove(member, from: pack) {
                    Button("Remove Member", systemImage: "person.badge.minus", role: .destructive) {
                        isConfirmingRemoval = true
                    }
                }
            }
            // An alert and not a confirmation dialog, as in the walk list.
            .alert("Remove \(member.fullName ?? PackMember.unknownName)?", isPresented: $isConfirmingRemoval) {
                Button("Cancel", role: .cancel) {}
                Button("Remove Member", role: .destructive, action: remove)
            } message: {
                if member.hasAccepted {
                    Text("The pack disappears from the iPhone of the member. The walks of the member stay with the dogs.")
                } else {
                    Text("The invitation no longer works for this person.")
                }
            }
            .alert("The member is still in the pack", isPresented: $removalFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check the internet connection and try again.")
            }
    }

    private func remove() {
        Task {
            do {
                try await packs.remove(member, from: pack)
            } catch {
                removalFailed = true
            }
        }
    }

    private var memberLabel: some View {
        LabeledContent {
            if member.isPackOwner {
                Text("Pack Owner")
            } else if !member.hasAccepted {
                Text("Invited")
            }
        } label: {
            // iCloud does not tell the pack owner their own name on their
            // phone, so this person shows as "You" without a name.
            if member.isThisPerson {
                if let name = member.fullName {
                    Text("\(name) (You)")
                } else {
                    Text("You")
                }
            } else {
                Text(member.fullName ?? PackMember.unknownName)
            }
        }
    }
}

/// The button with which a member who is not the pack owner leaves the pack.
/// The pack then disappears from the settings.
private struct LeavePackButton: View {
    @ObservedObject var pack: Pack

    @Environment(Packs.self) private var packs
    @State private var isConfirming = false
    @State private var leavingFailed = false

    var body: some View {
        if packs.mayLeave(pack) {
            Button("Leave Pack", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                isConfirming = true
            }
            .alert("Leave \(packs.shownName(of: pack))?", isPresented: $isConfirming) {
                Button("Cancel", role: .cancel) {}
                Button("Leave Pack", role: .destructive, action: leave)
            } message: {
                Text("The pack and its dogs disappear from this iPhone. Your walks stay with the dogs in the pack, but a walk that this iPhone has not uploaded yet is lost.")
            }
            .alert("You are still in the pack", isPresented: $leavingFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check the internet connection and try again.")
            }
        }
    }

    private func leave() {
        Task {
            do {
                try await packs.leave(pack)
            } catch {
                leavingFailed = true
            }
        }
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
