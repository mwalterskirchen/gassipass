//
//  AccountSection.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import SwiftData
import SwiftUI

/// The account in the settings. A person without an account signs in with
/// Apple. A signed-in member changes their name here, and sees whether every
/// change has uploaded. When the account is in another pack than this phone,
/// the person brings the dogs of this phone into it here (ADR 0005). The
/// person signs out and deletes their account here too.
struct AccountSection: View {
    @Environment(Account.self) private var account

    var body: some View {
        Section {
            if account.isSignedIn {
                MemberNameField()
                LabeledContent("Backup") {
                    if account.waitingChanges == 0 {
                        Text("Backed Up")
                    } else {
                        Text("\(account.waitingChanges) changes waiting")
                    }
                }
                if let packOfAccount = account.packOfAccount {
                    DogMoveRows(packOfAccount: packOfAccount)
                }
                SignOutButton()
                DeleteAccountButton()
            } else if account.canSignIn {
                SignInButton()
            } else {
                Text("This build cannot sign in.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Account")
        } footer: {
            if !account.isSignedIn {
                Text("With an account, your pack is backed up on the server. Without one, everything stays on this phone.")
            }
        }
    }
}

/// The pack of the account, which the dogs of this phone are not in yet, and
/// the button that brings them into it after a confirmation.
private struct DogMoveRows: View {
    let packOfAccount: ServerPack

    @Environment(Account.self) private var account
    @Query(Dog.all()) private var dogs: [Dog]
    @State private var isConfirming = false
    @State private var isMoving = false

    var body: some View {
        Text("Your account is a member of the pack «\(packName)». Your dogs on this phone are not in it yet, so nothing on this phone is backed up.")
            .foregroundStyle(.secondary)
        Button("Bring Dogs into Pack") {
            isConfirming = true
        }
        .disabled(isMoving)
        .confirmationDialog("Bring Dogs into Pack?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Bring Dogs") {
                move()
            }
        } message: {
            if dogs.isEmpty {
                Text("The pack on this phone has no dogs, and it disappears. This phone then shows the pack «\(packName)».")
            } else {
                Text("You bring \(dogs.map(\.name).formatted(.list(type: .and))) into the pack «\(packName)», with all walks and stamps. The pack on this phone then disappears.")
            }
        }
    }

    private var packName: String {
        Pack.shownName(packOfAccount.name)
    }

    private func move() {
        isMoving = true
        Task {
            await account.moveDogsIntoPackOfAccount()
            isMoving = false
        }
    }
}

/// Signs out after a confirmation, which warns when changes wait to upload,
/// because the sign-out removes the pack from the phone.
private struct SignOutButton: View {
    @Environment(Account.self) private var account
    @State private var isConfirming = false
    @State private var isSigningOut = false
    @State private var signOutFailed = false

    var body: some View {
        Button("Sign Out") {
            isConfirming = true
        }
        .disabled(isSigningOut)
        .confirmationDialog("Sign Out?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                signOut()
            }
        } message: {
            if account.waitingChanges == 0 {
                Text("Your pack leaves this phone, with its dogs and walks. It stays on the server and comes back when you sign in again.")
            } else {
                Text("\(account.waitingChanges) changes are not backed up yet, and they are lost when you sign out. Everything else stays on the server and comes back when you sign in again.")
            }
        }
        .alert("Sign-Out Failed", isPresented: $signOutFailed) {
        } message: {
            Text("Please try again later.")
        }
    }

    private func signOut() {
        isSigningOut = true
        Task {
            do {
                try await account.signOut()
            } catch {
                signOutFailed = true
            }
            isSigningOut = false
        }
    }
}

/// Deletes the account after a confirmation, which says what happens to the
/// pack (glossary, «Pack owner»).
private struct DeleteAccountButton: View {
    @Environment(Account.self) private var account
    @Query(Pack.all()) private var packs: [Pack]
    @State private var isConfirming = false
    @State private var isDeleting = false
    @State private var deletionFailed = false

    var body: some View {
        Button("Delete Account", role: .destructive) {
            isConfirming = true
        }
        .disabled(isDeleting)
        .confirmationDialog("Delete Account?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                delete()
            }
        } message: {
            message
        }
        .alert("Account Not Deleted", isPresented: $deletionFailed) {
        } message: {
            Text("The account cannot be deleted. Please check the connection and try again.")
        }
    }

    /// What happens to the pack, and the changes that are not backed up
    /// yet. The members load with each download, the pack owner first and
    /// then in the order of their join, so the next pack owner is the first
    /// other member. Before the first download, the members are unknown.
    private var message: Text {
        let otherMembers = account.packMembers.filter { !$0.isThisPerson }
        let packName = packs.first?.shownName ?? ""
        let consequence = if account.packMembers.isEmpty {
            String(localized: "Your account is deleted on the server and on this phone. This cannot be undone.")
        } else if let nextPackOwner = otherMembers.first, account.isPackOwner {
            String(localized: "Your account is deleted, and you leave the pack «\(packName)». \(nextPackOwner.shownName) becomes the pack owner, and your walks stay with the dogs. This cannot be undone.")
        } else if !otherMembers.isEmpty {
            String(localized: "Your account is deleted, and you leave the pack «\(packName)». Your walks stay with the dogs. This cannot be undone.")
        } else {
            String(localized: "Your account is deleted, with your pack and all its dogs, walks and stamps, on the server and on this phone. This cannot be undone.")
        }
        guard account.waitingChanges > 0 else { return Text(consequence) }
        let warning = String(localized: "\(account.waitingChanges) changes are not backed up yet. They are lost if they cannot upload before the deletion.")
        return Text(verbatim: "\(consequence) \(warning)")
    }

    private func delete() {
        isDeleting = true
        Task {
            do {
                try await account.deleteAccount()
            } catch {
                deletionFailed = true
            }
            isDeleting = false
        }
    }
}

/// The name of the member. The new name counts when the member leaves the
/// field.
private struct MemberNameField: View {
    @Environment(Account.self) private var account
    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Your Name", text: $name)
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .focused($isFocused)
            .onAppear {
                name = account.memberName
            }
            .onChange(of: account.memberName) {
                if !isFocused {
                    name = account.memberName
                }
            }
            .onChange(of: isFocused) {
                if !isFocused {
                    save()
                }
            }
            .onDisappear(perform: save)
    }

    private func save() {
        guard name != account.memberName else { return }
        let name = name
        Task {
            await account.renameMember(to: name)
        }
    }
}
