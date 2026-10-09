//
//  AppleSignIn.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import AuthenticationServices
import CryptoKit
import Foundation

/// The nonce of one Sign in with Apple. Apple gets its hash and puts it
/// into the ID token, and Supabase compares the hash of the nonce with it,
/// so that nobody can use the ID token again.
struct AppleSignInNonce {
    let value: String

    init() {
        value = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }

    /// The SHA-256 hash of the nonce, as Apple wants it.
    var hash: String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleCredential {
    /// The credential of a finished Sign in with Apple, or nil when Apple
    /// gave no ID token.
    init?(_ authorization: ASAuthorization, nonce: AppleSignInNonce) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) })
        else { return nil }
        self.init(idToken: token, nonce: nonce.value, givenName: credential.fullName?.givenName)
    }
}
