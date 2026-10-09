//
//  Server.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Foundation

/// The server of the app (ADR 0006), as the account sees it.
protocol Server {
    /// Whether the phone keeps the session of an account. It makes no request.
    var isSignedIn: Bool { get }
    /// Signs in with the ID token of Sign in with Apple, and keeps the session.
    func signIn(appleIDToken: String, nonce: String) async throws
    /// The member row of the account.
    func member() async throws -> ServerMember
    func renameMember(to name: String) async throws
    /// Makes the pack on the server, with this person as its pack owner and
    /// member. A second call for the same pack changes nothing.
    func createPack(id: UUID, name: String, createdAt: Date) async throws
    func renamePack(id: UUID, to name: String) async throws
}

/// The member row of an account on the server.
struct ServerMember: Equatable {
    var name: String
    /// The pack of the person, or nil for a person in no pack.
    var packID: UUID?
}
