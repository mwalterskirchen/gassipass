//
//  FakeServer.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Foundation
@testable import gassipass

/// A server in memory that keeps the rules of the real one: an account has
/// one member row, and a person in a pack cannot make a second pack.
final class FakeServer: Server {
    struct StoredPack: Equatable {
        var name: String
        var createdAt: Date
    }

    var isSignedIn = false
    var member = ServerMember(name: "", packID: nil)
    var packs: [UUID: StoredPack] = [:]
    /// The name of each call, in order.
    private(set) var requests: [String] = []
    /// The calls that fail once, with their names.
    var failingOnce: Set<String> = []

    struct Failure: Error {}

    func signIn(appleIDToken: String, nonce: String) async throws {
        try request("signIn")
        isSignedIn = true
    }

    func member() async throws -> ServerMember {
        try request("member")
        return member
    }

    func renameMember(to name: String) async throws {
        try request("renameMember")
        member.name = name
    }

    func createPack(id: UUID, name: String, createdAt: Date) async throws {
        try request("createPack")
        if member.packID == id { return }
        guard member.packID == nil, packs[id] == nil else { throw Failure() }
        packs[id] = StoredPack(name: name, createdAt: createdAt)
        member.packID = id
    }

    func renamePack(id: UUID, to name: String) async throws {
        try request("renamePack")
        guard member.packID == id else { return }
        packs[id]?.name = name
    }

    private func request(_ name: String) throws {
        requests.append(name)
        if failingOnce.remove(name) != nil {
            throw Failure()
        }
    }
}
