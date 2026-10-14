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
/// the person brings the dogs of this phone into it here (ADR 0005).
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
