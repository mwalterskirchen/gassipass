//
//  AccountSection.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import AuthenticationServices
import SwiftUI

/// The account in the settings. A person without an account signs in with
/// Apple. A signed-in member changes their name here.
struct AccountSection: View {
    @Environment(Account.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce = AppleSignInNonce()
    @State private var isSigningIn = false
    @State private var signInFailed = false

    var body: some View {
        Section {
            if account.isSignedIn {
                MemberNameField()
            } else if account.canSignIn {
                SignInWithAppleButton(.signIn) { request in
                    nonce = AppleSignInNonce()
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = nonce.hash
                } onCompletion: { result in
                    signIn(with: result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 44)
                .disabled(isSigningIn)
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
        .alert("Sign-In Failed", isPresented: $signInFailed) {
        } message: {
            Text("Please try again later.")
        }
    }

    private func signIn(with result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = AppleCredential(authorization, nonce: nonce) else {
                signInFailed = true
                return
            }
            isSigningIn = true
            Task {
                do {
                    try await account.signIn(with: credential)
                } catch {
                    signInFailed = true
                }
                isSigningIn = false
            }
        case .failure(let error):
            // The person closed the sheet of Apple.
            if (error as? ASAuthorizationError)?.code != .canceled {
                signInFailed = true
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
