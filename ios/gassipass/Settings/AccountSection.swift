//
//  AccountSection.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import SwiftUI

/// The account in the settings. A person without an account signs in with
/// Apple. A signed-in member changes their name here, and sees whether every
/// change has uploaded.
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
