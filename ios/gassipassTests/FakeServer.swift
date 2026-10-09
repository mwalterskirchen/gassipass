//
//  FakeServer.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Foundation
@testable import gassipass

/// A server in memory that keeps the rules of the real one: an account has
/// one member row, a person in a pack cannot make a second pack, a member
/// writes only into their pack, and a row points only to stored rows.
final class FakeServer: Server {
    struct StoredPack: Equatable {
        var name: String
        var createdAt: Date
    }

    var isSignedIn = false
    var member = ServerMember(name: "", packID: nil)
    var packs: [UUID: StoredPack] = [:]
    var dogs: [UUID: ServerDog] = [:]
    var walks: [UUID: ServerWalk] = [:]
    var walkDogs: [UUID: ServerWalkDog] = [:]
    var completedAreas: [UUID: ServerCompletedArea] = [:]
    var completedStreets: [UUID: ServerCompletedStreet] = [:]
    var files: [ServerFile: Data] = [:]
    /// The name of each call, in order.
    private(set) var requests: [String] = []
    /// The calls that fail once, with their names.
    var failingOnce: Set<String> = []
    /// Whether every call fails, like without a network.
    var isOffline = false
    /// The IDs of the rows that the server refuses, like a row that breaks a
    /// check constraint. A request with such a row fails as a whole.
    var refusedIDs: Set<UUID> = []

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

    func uploadDogs(_ dogs: [ServerDog]) async throws {
        try request("uploadDogs")
        try checkPack(of: dogs.map(\.packID))
        guard refusedIDs.isDisjoint(with: dogs.map(\.id)) else { throw Failure() }
        for dog in dogs {
            self.dogs[dog.id] = dog
        }
    }

    func uploadWalks(_ walks: [ServerWalk]) async throws {
        try request("uploadWalks")
        try checkPack(of: walks.map(\.packID))
        for walk in walks {
            self.walks[walk.id] = walk
        }
    }

    func uploadWalkDogs(_ walkDogs: [ServerWalkDog]) async throws {
        try request("uploadWalkDogs")
        try checkPack(of: walkDogs.map(\.packID))
        // The foreign keys.
        guard walkDogs.allSatisfy({ walks[$0.walkID] != nil && dogs[$0.dogID] != nil }) else { throw Failure() }
        for walkDog in walkDogs {
            self.walkDogs[walkDog.id] = walkDog
        }
    }

    func uploadCompletedAreas(_ records: [ServerCompletedArea]) async throws {
        try request("uploadCompletedAreas")
        try checkPack(of: records.map(\.packID))
        guard records.allSatisfy({ dogs[$0.dogID] != nil }) else { throw Failure() }
        for record in records {
            completedAreas[record.id] = record
        }
    }

    func uploadCompletedStreets(_ records: [ServerCompletedStreet]) async throws {
        try request("uploadCompletedStreets")
        try checkPack(of: records.map(\.packID))
        guard records.allSatisfy({ dogs[$0.dogID] != nil }) else { throw Failure() }
        for record in records {
            completedStreets[record.id] = record
        }
    }

    func uploadFile(_ data: Data, to file: ServerFile) async throws {
        try request("uploadFile")
        switch file {
        case .track(_, let pack), .dogPhoto(_, let pack):
            try checkPack(of: [pack])
        }
        files[file] = data
    }

    /// Row-level security: a member writes only into their pack.
    private func checkPack(of packIDs: [UUID]) throws {
        guard packIDs.allSatisfy({ $0 == member.packID }) else { throw Failure() }
    }

    private func request(_ name: String) throws {
        requests.append(name)
        if isOffline {
            throw URLError(.notConnectedToInternet)
        }
        if failingOnce.remove(name) != nil {
            throw Failure()
        }
    }
}
