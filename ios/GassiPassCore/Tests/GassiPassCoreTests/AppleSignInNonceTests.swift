//
//  AppleSignInNonceTests.swift
//  GassiPassCoreTests
//
//  Created by Maximilian Walterskirchen on 11.11.2026.
//

import CryptoKit
import Foundation
import Testing
@testable import GassiPassCore

/// The nonce of Sign in with Apple.
struct AppleSignInNonceTests {
    @Test func eachNonceIsNewAndHas32BytesAsHex() {
        let nonce = AppleSignInNonce()

        #expect(nonce.value.count == 64)
        #expect(nonce.value.allSatisfy { $0.isHexDigit })
        #expect(nonce.value != AppleSignInNonce().value)
    }

    @Test func theHashIsTheSHA256OfTheNonceAsHex() {
        let nonce = AppleSignInNonce()
        let expected = SHA256.hash(data: Data(nonce.value.utf8)).map { String(format: "%02x", $0) }.joined()

        #expect(nonce.hash == expected)
    }
}
