//
//  AppleSignInNonce.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 11.11.2026.
//

import CryptoKit
import Foundation

/// The nonce of one Sign in with Apple. Apple puts the hash of the nonce
/// into the ID token. Supabase compares that hash with the hash of the
/// nonce. So nobody can use the ID token again.
public nonisolated struct AppleSignInNonce: Sendable {
    public let value: String

    public init() {
        value = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }

    /// The SHA-256 hash of the nonce, as Apple wants it.
    public var hash: String {
        SHA256.hex(of: Data(value.utf8))
    }
}
