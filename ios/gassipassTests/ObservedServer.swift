//
//  ObservedServer.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
@testable import gassipass

/// A server for the tests that passes each request to another server, the
/// fake (`FakeServer`) or the local Supabase, and notes it first. It lets a
/// request fail, wait or see a change on the phone before it reaches the
/// other server. The properties of the other server read through it, for
/// example `server.dogs` of the fake. A property with the name of a call,
/// like `member` and `packMembers` of the fake, reads through `base`.
@dynamicMemberLookup
final class ObservedServer<Base: Server>: Server {
    /// The server that gets the requests.
    let base: Base

    /// The name of each call, in order, for example "uploadDogs".
    private(set) var requests: [String] = []
    /// The date that each download of a table asked for last, by the name
    /// of the call.
    private(set) var changedSince: [String: Date?] = [:]
    /// The calls that fail once, with their names.
    var failingOnce: Set<String> = []
    /// Whether every call fails, like without a network.
    var isOffline = false
    /// The IDs of the rows that the server refuses, like a row that breaks a
    /// check constraint. A request with such a row fails as a whole.
    var refusedIDs: Set<UUID> = []
    /// Runs before each call, with its name, for example to change a row on
    /// the phone during an upload.
    var beforeRequest: ((String) -> Void)?
    /// How long each download and each file request takes, so that requests
    /// can run at the same time. Without it, a request ends at once.
    var requestDelay: Duration?
    /// For each kind of request, the requests that ran when one of them
    /// started.
    private(set) var runningAtStart: [String: Set<String>] = [:]
    /// The most file requests that ran at the same time.
    var mostFilesAtOnce = 0
    /// The requests that run now, by their names.
    private var running: [String] = []

    init(_ base: Base) {
        self.base = base
    }

    subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<Base, Value>) -> Value {
        get { base[keyPath: keyPath] }
        set { base[keyPath: keyPath] = newValue }
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<Base, Value>) -> Value {
        base[keyPath: keyPath]
    }

    var isSignedIn: Bool {
        base.isSignedIn
    }

    func signIn(appleIDToken: String, nonce: String) async throws {
        try request("signIn")
        try await base.signIn(appleIDToken: appleIDToken, nonce: nonce)
    }

    func signOut() async {
        requests.append("signOut")
        await base.signOut()
    }

    func member() async throws -> ServerMember {
        try request("member")
        return try await base.member()
    }

    func renameMember(to name: String) async throws {
        try request("renameMember")
        try await base.renameMember(to: name)
    }

    func createPack(id: UUID, name: String, createdAt: Date) async throws {
        try request("createPack")
        try await base.createPack(id: id, name: name, createdAt: createdAt)
    }

    func updatePack(id: UUID, with change: ServerPackChange) async throws {
        try request("updatePack")
        try await base.updatePack(id: id, with: change)
    }

    func upload<Row: ServerRow>(_ rows: [Row]) async throws {
        try request(Self.requestName("upload", Row.table))
        guard refusedIDs.isDisjoint(with: rows.map(\.id)) else { throw RowRefused() }
        try await base.upload(rows)
    }

    func uploadFile(_ data: Data, to file: ServerFile) async throws {
        try request("uploadFile")
        try await take("uploadFile")
        try await base.uploadFile(data, to: file)
    }

    func deleteFile(_ file: ServerFile) async throws {
        try request("deleteFile")
        try await take("deleteFile")
        try await base.deleteFile(file)
    }

    func pack(id: UUID) async throws -> ServerPack? {
        try request("pack")
        try await take("pack")
        return try await base.pack(id: id)
    }

    func download<Row: ServerRow>(
        _ type: Row.Type, of pack: UUID, changedSince date: Date?
    ) async throws -> [Downloaded<Row>] {
        let name = Self.requestName("download", Row.table)
        try request(name)
        try await take(name)
        changedSince[name] = date
        return try await base.download(type, of: pack, changedSince: date)
    }

    func downloadFile(_ file: ServerFile) async throws -> Data {
        try request("downloadFile")
        try await take("downloadFile")
        return try await base.downloadFile(file)
    }

    func packMembers() async throws -> [PackMember] {
        try request("packMembers")
        try await take("packMembers")
        return try await base.packMembers()
    }

    func createInvitation() async throws -> String {
        try request("createInvitation")
        return try await base.createInvitation()
    }

    func checkInvitation(token: String) async throws -> Invitation {
        try request("checkInvitation")
        return try await base.checkInvitation(token: token)
    }

    func joinPack(token: String) async throws -> InvitationState {
        try request("joinPack")
        return try await base.joinPack(token: token)
    }

    func hasMovedIntoPackOfAccount(pack: UUID) async throws -> Bool {
        try request("hasMovedIntoPackOfAccount")
        return try await base.hasMovedIntoPackOfAccount(pack: pack)
    }

    func leavePack() async throws {
        try request("leavePack")
        try await base.leavePack()
    }

    func removeMember(id: UUID) async throws {
        try request("removeMember")
        try await base.removeMember(id: id)
    }

    func hasLeftPack(_ pack: UUID) async throws -> Bool {
        try request("hasLeftPack")
        return try await base.hasLeftPack(pack)
    }

    func packsDeletedWithAccount() async throws -> [UUID] {
        try request("packsDeletedWithAccount")
        return try await base.packsDeletedWithAccount()
    }

    func deleteFiles(ofPack pack: UUID) async throws {
        try request("deleteFiles")
        try await base.deleteFiles(ofPack: pack)
    }

    func deleteAccount() async throws {
        try request("deleteAccount")
        try await base.deleteAccount()
    }

    /// The name of a request for a table, for example "uploadWalkDogs".
    private static func requestName(_ verb: String, _ table: ServerTable) -> String {
        verb + table.rawValue.split(separator: "_").map(\.capitalized).joined()
    }

    /// Notes the request, and lets it fail without a network or once.
    private func request(_ name: String) throws {
        requests.append(name)
        beforeRequest?(name)
        if isOffline {
            throw URLError(.notConnectedToInternet)
        }
        if failingOnce.remove(name) != nil {
            throw InjectedFailure()
        }
    }

    /// Lets the request take the time of `requestDelay`, and notes which
    /// requests run at the same time.
    private func take(_ name: String) async throws {
        runningAtStart[name, default: []].formUnion(running)
        running.append(name)
        defer {
            if let index = running.firstIndex(of: name) {
                running.remove(at: index)
            }
        }
        mostFilesAtOnce = max(mostFilesAtOnce, running.count { $0.hasSuffix("File") })
        if let requestDelay {
            try await Task.sleep(for: requestDelay)
        }
    }
}

/// The failure of a call in `ObservedServer.failingOnce`.
struct InjectedFailure: Error {}
