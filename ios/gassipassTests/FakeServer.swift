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
/// writes and reads only their pack, and a row points only to stored rows.
/// The only member of a pack who joins another pack brings their dogs.
/// Each write notes the time of the change on a clock of the server, which
/// moves one second for each write.
///
/// Two phones of the same account share one fake server.
final class FakeServer: Server {
    struct StoredPack: Equatable {
        var name: String
        var createdAt: Date
    }

    struct StoredInvitation: Equatable {
        var packID: UUID
        var packOwnerName: String
        var isUsed = false
        var isExpired = false
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
    /// The members of the pack of the account, as the server gives them.
    var packMembers: [PackMember] = []
    /// The invitations, by their token.
    var invitations: [String: StoredInvitation] = [:]
    /// The pack that each moved pack moved into, by the ID of the moved
    /// pack.
    private(set) var movedPacks: [UUID: UUID] = [:]
    /// The time of the last change of each row, by its ID.
    private(set) var changedAt: [UUID: Date] = [:]
    /// The clock of the server.
    private(set) var now = Date(timeIntervalSince1970: 1_800_000_000)
    /// The date that each download of a table asked for last, by the name
    /// of the call.
    private(set) var changedSince: [String: Date?] = [:]
    /// The name of each call, in order.
    private(set) var requests: [String] = []
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
        try checkRefused(dogs.map(\.id))
        for dog in dogs {
            self.dogs[dog.id] = dog
            noteChange(of: dog.id)
        }
    }

    func uploadWalks(_ walks: [ServerWalk]) async throws {
        try request("uploadWalks")
        try checkPack(of: walks.map(\.packID))
        try checkRefused(walks.map(\.id))
        for walk in walks {
            self.walks[walk.id] = walk
            noteChange(of: walk.id)
        }
    }

    func uploadWalkDogs(_ walkDogs: [ServerWalkDog]) async throws {
        try request("uploadWalkDogs")
        try checkPack(of: walkDogs.map(\.packID))
        // The foreign keys.
        guard walkDogs.allSatisfy({ walks[$0.walkID] != nil && dogs[$0.dogID] != nil }) else { throw RowRefused() }
        try checkRefused(walkDogs.map(\.id))
        for walkDog in walkDogs {
            self.walkDogs[walkDog.id] = walkDog
            noteChange(of: walkDog.id)
        }
    }

    func uploadCompletedAreas(_ records: [ServerCompletedArea]) async throws {
        try request("uploadCompletedAreas")
        try checkPack(of: records.map(\.packID))
        guard records.allSatisfy({ dogs[$0.dogID] != nil }) else { throw RowRefused() }
        try checkRefused(records.map(\.id))
        for record in records {
            completedAreas[record.id] = record
            noteChange(of: record.id)
        }
    }

    func uploadCompletedStreets(_ records: [ServerCompletedStreet]) async throws {
        try request("uploadCompletedStreets")
        try checkPack(of: records.map(\.packID))
        guard records.allSatisfy({ dogs[$0.dogID] != nil }) else { throw RowRefused() }
        try checkRefused(records.map(\.id))
        for record in records {
            completedStreets[record.id] = record
            noteChange(of: record.id)
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

    func deleteFile(_ file: ServerFile) async throws {
        try request("deleteFile")
        switch file {
        case .track(_, let pack), .dogPhoto(_, let pack):
            try checkPack(of: [pack])
        }
        files[file] = nil
    }

    func pack(id: UUID) async throws -> ServerPack? {
        try request("pack")
        guard member.packID == id, let pack = packs[id] else { return nil }
        return ServerPack(id: id, name: pack.name, createdAt: pack.createdAt)
    }

    func downloadDogs(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerDog>] {
        try download("downloadDogs", from: dogs, of: pack, changedSince: date)
    }

    func downloadWalks(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerWalk>] {
        try download("downloadWalks", from: walks, of: pack, changedSince: date)
    }

    func downloadWalkDogs(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerWalkDog>] {
        try download("downloadWalkDogs", from: walkDogs, of: pack, changedSince: date)
    }

    func downloadCompletedAreas(
        of pack: UUID, changedSince date: Date?
    ) async throws -> [Downloaded<ServerCompletedArea>] {
        try download("downloadCompletedAreas", from: completedAreas, of: pack, changedSince: date)
    }

    func downloadCompletedStreets(
        of pack: UUID, changedSince date: Date?
    ) async throws -> [Downloaded<ServerCompletedStreet>] {
        try download("downloadCompletedStreets", from: completedStreets, of: pack, changedSince: date)
    }

    func downloadFile(_ file: ServerFile) async throws -> Data {
        try request("downloadFile")
        switch file {
        case .track(_, let pack), .dogPhoto(_, let pack):
            guard member.packID == pack else { throw RowRefused() }
        }
        guard let data = files[file] else { throw Failure() }
        return data
    }

    func packMembers() async throws -> [PackMember] {
        try request("packMembers")
        return member.packID == nil ? [] : packMembers
    }

    func createInvitation() async throws -> String {
        try request("createInvitation")
        guard let packID = member.packID, packMembers.contains(where: { $0.isThisPerson && $0.isPackOwner })
        else { throw Failure() }
        let token = "token-\(invitations.count + 1)"
        invitations[token] = StoredInvitation(
            packID: packID, packOwnerName: packMembers.first(where: \.isPackOwner)?.name ?? "")
        return token
    }

    func checkInvitation(token: String) async throws -> Invitation {
        try request("checkInvitation")
        guard let invitation = invitations[token] else {
            return Invitation(state: .unknown, packID: nil, packName: "", packOwnerName: "")
        }
        return Invitation(
            state: state(of: invitation), packID: invitation.packID, packName: packs[invitation.packID]?.name ?? "",
            packOwnerName: invitation.packOwnerName)
    }

    func joinPack(token: String) async throws -> InvitationState {
        try request("joinPack")
        guard let invitation = invitations[token] else { return .unknown }
        let state = state(of: invitation)
        guard state == .open else { return state }
        if let oldPack = member.packID {
            move(oldPack, into: invitation.packID)
        }
        invitations[token]?.isUsed = true
        member.packID = invitation.packID
        return .joined
    }

    func hasMovedIntoPackOfAccount(pack: UUID) async throws -> Bool {
        try request("hasMovedIntoPackOfAccount")
        return member.packID != nil && movedPacks[pack] == member.packID
    }

    /// The rules of the server, in the same order. The members of the pack
    /// of the account are in `packMembers`.
    private func state(of invitation: StoredInvitation) -> InvitationState {
        if member.packID == invitation.packID { return .member }
        if invitation.isUsed { return .used }
        if invitation.isExpired { return .expired }
        if member.packID != nil, packMembers.count > 1 { return .inOtherPack }
        return .open
    }

    /// Moves the rows of the old pack into the new pack, each with a new
    /// change, and lets the old pack disappear.
    private func move(_ oldPack: UUID, into newPack: UUID) {
        func move<Row: ServerRow>(_ rows: inout [UUID: Row], _ packID: WritableKeyPath<Row, UUID>) {
            for (id, row) in rows where row.packID == oldPack {
                rows[id]?[keyPath: packID] = newPack
                noteChange(of: id)
            }
        }
        move(&dogs, \.packID)
        move(&walks, \.packID)
        move(&walkDogs, \.packID)
        move(&completedAreas, \.packID)
        move(&completedStreets, \.packID)
        packs[oldPack] = nil
        movedPacks[oldPack] = newPack
    }

    /// Notes a change of the row that another phone of the pack made.
    func noteChange(of id: UUID) {
        now += 1
        changedAt[id] = now
    }

    /// The rows of the pack that changed at the date or later, the oldest
    /// change first.
    private func download<Row: ServerRow>(
        _ name: String, from rows: [UUID: Row], of pack: UUID, changedSince date: Date?
    ) throws -> [Downloaded<Row>] {
        try request(name)
        changedSince[name] = date
        guard member.packID == pack else { return [] }
        return try rows.values.compactMap { row -> Downloaded<Row>? in
            guard let changedAt = changedAt[row.id], changedAt >= date ?? .distantPast, row.packID == pack
            else { return nil }
            return Downloaded(row: try Self.withMilliseconds(row), changedAt: changedAt)
        }
        .sorted { $0.changedAt < $1.changedAt }
    }

    /// The row as Supabase gives it back: the client sends each date with
    /// milliseconds only.
    private static func withMilliseconds<Row: ServerRow>(_ row: Row) throws -> Row {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = formatter.date(from: text) else { throw Failure() }
            return date
        }
        return try decoder.decode(Row.self, from: encoder.encode(row))
    }

    /// Row-level security: a member writes only into their pack.
    private func checkPack(of packIDs: [UUID]) throws {
        guard packIDs.allSatisfy({ $0 == member.packID }) else { throw RowRefused() }
    }

    private func checkRefused(_ ids: [UUID]) throws {
        guard refusedIDs.isDisjoint(with: ids) else { throw RowRefused() }
    }

    private func request(_ name: String) throws {
        requests.append(name)
        beforeRequest?(name)
        if isOffline {
            throw URLError(.notConnectedToInternet)
        }
        if failingOnce.remove(name) != nil {
            throw Failure()
        }
    }
}
