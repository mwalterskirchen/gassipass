//
//  FakeServer.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import CryptoKit
import Foundation
@testable import gassipass

/// A server in memory that keeps the rules of the real one: an account has
/// one member row, a person in a pack cannot make a second pack, a member
/// writes and reads only their pack, and a row points only to stored rows.
/// The only member of a pack who joins another pack brings their dogs. Only
/// the pack owner removes a member, and the pack owner cannot leave.
/// Each write notes the time of the change on a clock of the server, which
/// moves one second for each write. `ServerContractTests` checks the rules
/// against the local Supabase. The tests wrap it in `ObservedServer`, which
/// notes the requests and lets them fail or wait.
///
/// Two phones of the same account share one fake server.
final class FakeServer: Server {
    struct StoredPack: Equatable {
        var name: String
        var createdAt: Date
        var homeBase: HomeBase? = nil
        var homeSetAt: Date? = nil
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
    /// The rows of each table, by their IDs.
    private var tables: [ServerTable: [UUID: any ServerRow]] = [:]
    var files: [ServerFile: Data] = [:]
    /// The members of the pack of the account, as the server gives them.
    var packMembers: [PackMember] = []
    /// The invitations, by their token.
    var invitations: [String: StoredInvitation] = [:]
    /// The pack that each moved pack moved into, by the ID of the moved
    /// pack.
    private(set) var movedPacks: [UUID: UUID] = [:]
    /// The packs that the account has left, or that the pack owner removed
    /// it from.
    private(set) var departures: Set<UUID> = []
    /// The time of the last change of each row, by its ID.
    private(set) var changedAt: [UUID: Date] = [:]
    /// The clock of the server.
    private(set) var now = Date(timeIntervalSince1970: 1_800_000_000)
    /// Whether the person has deleted their account.
    private(set) var isAccountDeleted = false

    struct Failure: Error {}

    var dogs: [UUID: ServerDog] {
        get { rows(ServerDog.self) }
        set { setRows(newValue) }
    }

    var walks: [UUID: ServerWalk] {
        get { rows(ServerWalk.self) }
        set { setRows(newValue) }
    }

    var walkDogs: [UUID: ServerWalkDog] {
        get { rows(ServerWalkDog.self) }
        set { setRows(newValue) }
    }

    var completedAreas: [UUID: ServerCompletedArea] {
        get { rows(ServerCompletedArea.self) }
        set { setRows(newValue) }
    }

    var completedStreets: [UUID: ServerCompletedStreet] {
        get { rows(ServerCompletedStreet.self) }
        set { setRows(newValue) }
    }

    var areaSteps: [UUID: ServerAreaStep] {
        get { rows(ServerAreaStep.self) }
        set { setRows(newValue) }
    }

    var completedRings: [UUID: ServerCompletedRing] {
        get { rows(ServerCompletedRing.self) }
        set { setRows(newValue) }
    }

    var weeklyGoals: [UUID: ServerGoalSet] {
        get { rows(ServerGoalSet.self) }
        set { setRows(newValue) }
    }

    /// The stored rows of the table of the type.
    private func rows<Row: ServerRow>(_ type: Row.Type) -> [UUID: Row] {
        (tables[Row.table] ?? [:]).compactMapValues { $0 as? Row }
    }

    private func setRows<Row: ServerRow>(_ rows: [UUID: Row]) {
        tables[Row.table] = rows
    }

    func signIn(appleIDToken: String, nonce: String) async throws {
        isSignedIn = true
    }

    func signOut() async {
        isSignedIn = false
    }

    func member() async throws -> ServerMember {
        return member
    }

    func renameMember(to name: String) async throws {
        member.name = name
    }

    func createPack(id: UUID, name: String, createdAt: Date) async throws {
        if member.packID == id { return }
        guard member.packID == nil, packs[id] == nil else { throw Failure() }
        packs[id] = StoredPack(name: name, createdAt: createdAt)
        member.packID = id
    }

    /// A change without a home base keeps the stored home base.
    func updatePack(id: UUID, with change: ServerPackChange) async throws {
        guard member.packID == id else { return }
        packs[id]?.name = change.name
        if let homeBase = change.homeBase {
            packs[id]?.homeBase = homeBase
            packs[id]?.homeSetAt = change.homeSetAt
        }
    }

    /// Keeps the rules of each table: a row points only to stored rows, and
    /// a dog keeps a photo path that Storage has. The weekly goals keep one
    /// set for each dog and week, the earliest finish of each goal, and one
    /// swap that changes only its own slot.
    func upload<Row: ServerRow>(_ rows: [Row]) async throws {
        try checkPack(of: rows.map(\.packID))
        // The foreign keys.
        guard rows.allSatisfy({ targets(of: $0).allSatisfy { tables[$0.table]?[$0.id] != nil } }) else {
            throw RowRefused()
        }
        switch rows {
        case let dogs as [ServerDog]:
            for var dog in dogs {
                // A dog keeps a photo path that Storage has
                // (`keep_photo_path_in_storage`).
                if let stored = self.dogs[dog.id], let path = dog.photoPath, path != stored.photoPath,
                   files[ServerFile(bucket: .dogPhotos, path: path)] == nil {
                    dog.photoPath = stored.photoPath
                }
                store(dog)
            }
        case let sets as [ServerGoalSet]:
            try storeWeeklyGoals(sets)
        default:
            for row in rows {
                store(row)
            }
        }
    }

    /// The rows that the row points to, by their table and ID.
    private func targets(of row: any ServerRow) -> [(table: ServerTable, id: UUID)] {
        switch row {
        case let walkDog as ServerWalkDog: [(.walks, walkDog.walkID), (.dogs, walkDog.dogID)]
        case let record as ServerCompletedArea: [(.dogs, record.dogID)]
        case let record as ServerCompletedStreet: [(.dogs, record.dogID)]
        case let step as ServerAreaStep: [(.dogs, step.dogID)]
        case let ring as ServerCompletedRing: [(.dogs, ring.dogID)]
        case let set as ServerGoalSet: [(.dogs, set.dogID)]
        default: []
        }
    }

    private func storeWeeklyGoals(_ sets: [ServerGoalSet]) throws {
        var stored = weeklyGoals
        for var set in sets {
            if stored.values.contains(where: {
                $0.id != set.id && $0.dogID == set.dogID && $0.weekStart == set.weekStart && $0.deletedAt == nil
            }) {
                throw RowRefused()
            }
            if let old = stored[set.id] {
                let changed = (0..<WeeklyGoalSet.slotCount).filter { set.slots[$0].goal != old.slots[$0].goal }
                let isSwap = old.swappedSlot == nil && set.swappedSlot.map { changed.allSatisfy([$0 - 1].contains) } == true
                guard (changed.isEmpty && set.swappedSlot == old.swappedSlot) || isSwap else { throw RowRefused() }
                for slot in 0..<WeeklyGoalSet.slotCount where !(isSwap && set.swappedSlot == slot + 1) {
                    set.slots[slot].finishedAt = [old.slots[slot].finishedAt, set.slots[slot].finishedAt]
                        .compactMap { $0 }.min()
                }
            }
            stored[set.id] = set
        }
        weeklyGoals = stored
        for set in sets {
            noteChange(of: set.id)
        }
    }

    /// Stores the row, and notes its change.
    private func store<Row: ServerRow>(_ row: Row) {
        tables[Row.table, default: [:]][row.id] = row
        noteChange(of: row.id)
    }

    func uploadFile(_ data: Data, to file: ServerFile) async throws {
        guard let pack = file.pack else { throw RowRefused() }
        try checkPack(of: [pack])
        files[file] = data
    }

    func deleteFile(_ file: ServerFile) async throws {
        try checkReads(file)
        files[file] = nil
    }

    func pack(id: UUID) async throws -> ServerPack? {
        guard member.packID == id, let pack = packs[id] else { return nil }
        return ServerPack(
            id: id, name: pack.name, createdAt: pack.createdAt, homeLatitude: pack.homeBase?.latitude,
            homeLongitude: pack.homeBase?.longitude, homeSetAt: pack.homeSetAt)
    }

    func download<Row: ServerRow>(
        _ type: Row.Type, of pack: UUID, changedSince date: Date?
    ) async throws -> [Downloaded<Row>] {
        guard member.packID == pack else { return [] }
        return try rows(type).values.compactMap { row -> Downloaded<Row>? in
            guard let changedAt = changedAt[row.id], changedAt >= date ?? .distantPast, row.packID == pack
            else { return nil }
            return Downloaded(row: try Self.withMilliseconds(row), changedAt: changedAt)
        }
        .sorted { $0.changedAt < $1.changedAt }
    }

    func downloadFile(_ file: ServerFile) async throws -> Data {
        try checkReads(file)
        guard let data = files[file] else { throw FileMissing() }
        return data
    }

    func packMembers() async throws -> [PackMember] {
        return member.packID == nil ? [] : packMembers
    }

    func createInvitation() async throws -> String {
        guard let packID = member.packID, packMembers.contains(where: { $0.isThisPerson && $0.isPackOwner })
        else { throw Failure() }
        let token = "token-\(invitations.count + 1)"
        invitations[token] = StoredInvitation(
            packID: packID, packOwnerName: packMembers.first(where: \.isPackOwner)?.name ?? "")
        return token
    }

    func checkInvitation(token: String) async throws -> Invitation {
        guard let invitation = invitations[token] else {
            return Invitation(state: .unknown, packID: nil, packName: "", packOwnerName: "")
        }
        return Invitation(
            state: state(of: invitation), packID: invitation.packID, packName: packs[invitation.packID]?.name ?? "",
            packOwnerName: invitation.packOwnerName)
    }

    func joinPack(token: String) async throws -> InvitationState {
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
        return hasMovedIntoPackOfMember(pack)
    }

    func leavePack() async throws {
        guard member.packID != nil else { return }
        guard !packMembers.contains(where: { $0.isThisPerson && $0.isPackOwner }) else { throw Failure() }
        takeAccountOutOfPack()
    }

    func removeMember(id: UUID) async throws {
        guard member.packID != nil, packMembers.contains(where: { $0.isThisPerson && $0.isPackOwner }),
              let removed = packMembers.first(where: { $0.id == id }), !removed.isThisPerson
        else { throw Failure() }
        packMembers.removeAll { $0.id == id }
    }

    func hasLeftPack(_ pack: UUID) async throws -> Bool {
        return departures.contains(pack) && member.packID != pack
    }

    /// Takes the account out of its pack, like the pack owner who removes
    /// the person on their phone.
    func takeAccountOutOfPack() {
        guard let packID = member.packID else { return }
        departures.insert(packID)
        member.packID = nil
        packMembers.removeAll { $0.isThisPerson }
    }

    func packsDeletedWithAccount() async throws -> [UUID] {
        guard let packID = member.packID, packMembers.count <= 1 else { return [] }
        return [packID] + movedPacks.filter { $0.value == packID }.map(\.key)
    }

    func deleteFiles(ofPack pack: UUID) async throws {
        guard member.packID == pack || hasMovedIntoPackOfMember(pack) else { throw RowRefused() }
        files = files.filter { $0.key.pack != pack }
    }

    func deleteAccount() async throws {
        if let packID = member.packID, packMembers.count <= 1 {
            let deletedPacks = Set(try await packsDeletedWithAccount())
            guard !files.keys.contains(where: { $0.pack.map(deletedPacks.contains) == true }) else { throw Failure() }
            tables = tables.mapValues { $0.filter { $0.value.packID != packID } }
            for pack in deletedPacks {
                packs[pack] = nil
            }
        }
        member = ServerMember(name: "", packID: nil)
        packMembers = []
        isAccountDeleted = true
    }

    private func hasMovedIntoPackOfMember(_ pack: UUID) -> Bool {
        member.packID != nil && movedPacks[pack] == member.packID
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
        for (table, rows) in tables {
            for (id, var row) in rows where row.packID == oldPack {
                row.packID = newPack
                tables[table]?[id] = row
                noteChange(of: id)
            }
        }
        packs[oldPack] = nil
        movedPacks[oldPack] = newPack
    }

    /// Moves the clock of the server.
    func passTime(_ interval: TimeInterval) {
        now += interval
    }

    /// Notes a change of the row that another phone of the pack made.
    func noteChange(of id: UUID) {
        now += 1
        changedAt[id] = now
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

    /// The policies of Storage: a member reads and deletes the files of their
    /// pack, and of each pack that moved into it.
    private func checkReads(_ file: ServerFile) throws {
        guard let pack = file.pack, member.packID == pack || hasMovedIntoPackOfMember(pack) else {
            throw RowRefused()
        }
    }
}

extension ServerFile {
    /// The pack whose folder the file is in, or nil.
    var pack: UUID? {
        UUID(uuidString: String(path.prefix { $0 != "/" }))
    }

    /// The version of the photo of a dog with this content.
    static func dogPhoto(dog: UUID, pack: UUID, data: Data) -> ServerFile {
        .dogPhoto(dog: dog, pack: pack, hash: SHA256.hex(of: data))
    }
}
