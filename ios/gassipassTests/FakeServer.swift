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
/// moves one second for each write.
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
    var dogs: [UUID: ServerDog] = [:]
    var walks: [UUID: ServerWalk] = [:]
    var walkDogs: [UUID: ServerWalkDog] = [:]
    var completedAreas: [UUID: ServerCompletedArea] = [:]
    var completedStreets: [UUID: ServerCompletedStreet] = [:]
    var areaSteps: [UUID: ServerAreaStep] = [:]
    var completedRings: [UUID: ServerCompletedRing] = [:]
    var weeklyGoals: [UUID: ServerWeeklyGoals] = [:]
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
    /// The date that each download of a table asked for last, by the name
    /// of the call.
    private(set) var changedSince: [String: Date?] = [:]
    /// Whether the person has deleted their account.
    private(set) var isAccountDeleted = false
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

    struct Failure: Error {}

    func signIn(appleIDToken: String, nonce: String) async throws {
        try request("signIn")
        isSignedIn = true
    }

    func signOut() async {
        requests.append("signOut")
        isSignedIn = false
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

    /// A change without a home base keeps the stored home base.
    func updatePack(id: UUID, with change: ServerPackChange) async throws {
        try request("updatePack")
        guard member.packID == id else { return }
        packs[id]?.name = change.name
        if let homeBase = change.homeBase {
            packs[id]?.homeBase = homeBase
            packs[id]?.homeSetAt = change.homeSetAt
        }
    }

    func uploadDogs(_ dogs: [ServerDog]) async throws {
        try request("uploadDogs")
        try checkPack(of: dogs.map(\.packID))
        try checkRefused(dogs.map(\.id))
        for var dog in dogs {
            // A dog keeps a photo path that Storage has
            // (`keep_photo_path_in_storage`).
            if let stored = self.dogs[dog.id], let path = dog.photoPath, path != stored.photoPath,
               files[ServerFile(bucket: .dogPhotos, path: path)] == nil {
                dog.photoPath = stored.photoPath
            }
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

    func uploadAreaSteps(_ steps: [ServerAreaStep]) async throws {
        try request("uploadAreaSteps")
        try checkPack(of: steps.map(\.packID))
        guard steps.allSatisfy({ dogs[$0.dogID] != nil }) else { throw RowRefused() }
        try checkRefused(steps.map(\.id))
        for step in steps {
            areaSteps[step.id] = step
            noteChange(of: step.id)
        }
    }

    func uploadCompletedRings(_ rings: [ServerCompletedRing]) async throws {
        try request("uploadCompletedRings")
        try checkPack(of: rings.map(\.packID))
        guard rings.allSatisfy({ dogs[$0.dogID] != nil }) else { throw RowRefused() }
        try checkRefused(rings.map(\.id))
        for ring in rings {
            completedRings[ring.id] = ring
            noteChange(of: ring.id)
        }
    }

    /// Keeps the rules of the table: one set for each dog and week, the
    /// earliest finish of each goal, and one swap that changes only its own
    /// slot.
    func uploadWeeklyGoals(_ sets: [ServerWeeklyGoals]) async throws {
        try request("uploadWeeklyGoals")
        try checkPack(of: sets.map(\.packID))
        guard sets.allSatisfy({ dogs[$0.dogID] != nil }) else { throw RowRefused() }
        try checkRefused(sets.map(\.id))
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

    func uploadFile(_ data: Data, to file: ServerFile) async throws {
        try request("uploadFile")
        try await take("uploadFile")
        guard let pack = file.pack else { throw RowRefused() }
        try checkPack(of: [pack])
        files[file] = data
    }

    func deleteFile(_ file: ServerFile) async throws {
        try request("deleteFile")
        try await take("deleteFile")
        try checkReads(file)
        files[file] = nil
    }

    func pack(id: UUID) async throws -> ServerPack? {
        try request("pack")
        try await take("pack")
        guard member.packID == id, let pack = packs[id] else { return nil }
        return ServerPack(
            id: id, name: pack.name, createdAt: pack.createdAt, homeLatitude: pack.homeBase?.latitude,
            homeLongitude: pack.homeBase?.longitude, homeSetAt: pack.homeSetAt)
    }

    func downloadDogs(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerDog>] {
        try await download("downloadDogs", from: dogs, of: pack, changedSince: date)
    }

    func downloadWalks(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerWalk>] {
        try await download("downloadWalks", from: walks, of: pack, changedSince: date)
    }

    func downloadWalkDogs(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerWalkDog>] {
        try await download("downloadWalkDogs", from: walkDogs, of: pack, changedSince: date)
    }

    func downloadCompletedAreas(
        of pack: UUID, changedSince date: Date?
    ) async throws -> [Downloaded<ServerCompletedArea>] {
        try await download("downloadCompletedAreas", from: completedAreas, of: pack, changedSince: date)
    }

    func downloadCompletedStreets(
        of pack: UUID, changedSince date: Date?
    ) async throws -> [Downloaded<ServerCompletedStreet>] {
        try await download("downloadCompletedStreets", from: completedStreets, of: pack, changedSince: date)
    }

    func downloadAreaSteps(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerAreaStep>] {
        try await download("downloadAreaSteps", from: areaSteps, of: pack, changedSince: date)
    }

    func downloadCompletedRings(
        of pack: UUID, changedSince date: Date?
    ) async throws -> [Downloaded<ServerCompletedRing>] {
        try await download("downloadCompletedRings", from: completedRings, of: pack, changedSince: date)
    }

    func downloadWeeklyGoals(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerWeeklyGoals>] {
        try await download("downloadWeeklyGoals", from: weeklyGoals, of: pack, changedSince: date)
    }

    func downloadFile(_ file: ServerFile) async throws -> Data {
        try request("downloadFile")
        try await take("downloadFile")
        try checkReads(file)
        guard let data = files[file] else { throw FileMissing() }
        return data
    }

    func packMembers() async throws -> [PackMember] {
        try request("packMembers")
        try await take("packMembers")
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
        return hasMovedIntoPackOfMember(pack)
    }

    func leavePack() async throws {
        try request("leavePack")
        guard member.packID != nil else { return }
        guard !packMembers.contains(where: { $0.isThisPerson && $0.isPackOwner }) else { throw Failure() }
        takeAccountOutOfPack()
    }

    func removeMember(id: UUID) async throws {
        try request("removeMember")
        guard member.packID != nil, packMembers.contains(where: { $0.isThisPerson && $0.isPackOwner }),
              let removed = packMembers.first(where: { $0.id == id }), !removed.isThisPerson
        else { throw Failure() }
        packMembers.removeAll { $0.id == id }
    }

    func hasLeftPack(_ pack: UUID) async throws -> Bool {
        try request("hasLeftPack")
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
        try request("packsDeletedWithAccount")
        guard let packID = member.packID, packMembers.count <= 1 else { return [] }
        return [packID] + movedPacks.filter { $0.value == packID }.map(\.key)
    }

    func deleteFiles(ofPack pack: UUID) async throws {
        try request("deleteFiles")
        guard member.packID == pack || hasMovedIntoPackOfMember(pack) else { throw RowRefused() }
        files = files.filter { $0.key.pack != pack }
    }

    func deleteAccount() async throws {
        try request("deleteAccount")
        if let packID = member.packID, packMembers.count <= 1 {
            let deletedPacks = Set(try await packsDeletedWithAccount())
            guard !files.keys.contains(where: { $0.pack.map(deletedPacks.contains) == true }) else { throw Failure() }
            dogs = dogs.filter { $0.value.packID != packID }
            walks = walks.filter { $0.value.packID != packID }
            walkDogs = walkDogs.filter { $0.value.packID != packID }
            completedAreas = completedAreas.filter { $0.value.packID != packID }
            completedStreets = completedStreets.filter { $0.value.packID != packID }
            areaSteps = areaSteps.filter { $0.value.packID != packID }
            completedRings = completedRings.filter { $0.value.packID != packID }
            weeklyGoals = weeklyGoals.filter { $0.value.packID != packID }
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
        move(&areaSteps, \.packID)
        move(&completedRings, \.packID)
        move(&weeklyGoals, \.packID)
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

    /// The rows of the pack that changed at the date or later, the oldest
    /// change first.
    private func download<Row: ServerRow>(
        _ name: String, from rows: [UUID: Row], of pack: UUID, changedSince date: Date?
    ) async throws -> [Downloaded<Row>] {
        try request(name)
        try await take(name)
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

    /// The policies of Storage: a member reads and deletes the files of their
    /// pack, and of each pack that moved into it.
    private func checkReads(_ file: ServerFile) throws {
        guard let pack = file.pack, member.packID == pack || hasMovedIntoPackOfMember(pack) else {
            throw RowRefused()
        }
    }

    private func checkRefused(_ ids: [UUID]) throws {
        guard refusedIDs.isDisjoint(with: ids) else { throw RowRefused() }
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
