//
//  SignInButton.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 14.10.2026.
//

import AuthenticationServices
import SwiftUI

/// The button of Sign in with Apple, which signs in the account, or a note
/// when the build cannot sign in.
struct SignInButton: View {
    @Environment(Account.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce = AppleSignInNonce()
    @State private var isSigningIn = false
    @State private var signInFailed = false

    var body: some View {
        if account.canSignIn {
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
            .alert("Sign-In Failed", isPresented: $signInFailed) {
            } message: {
                Text("Please try again later.")
            }
        } else {
            Text("This build cannot sign in.")
                .foregroundStyle(.secondary)
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
