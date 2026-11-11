//
//  AppleSignIn.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import AuthenticationServices
import Foundation
import GassiPassCore

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
