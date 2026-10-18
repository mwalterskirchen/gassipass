//
//  ServerContractTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import Testing
@testable import gassipass

/// The rules of the server that the phone relies on, for one account. Each
/// test runs against the fake (`FakeServer`) and against the local Supabase
/// when it runs, so the fake cannot keep a rule that the real server does not
/// have. A test uses only the `Server` interface.
///
/// The rules that need several accounts stay outside: the members of a pack,
/// invitations, joins and moves, leaving and removing, and the deletion of an
/// account. `LocalSupabaseInvitationTests` and `LocalSupabaseAccountDeletionTests`
/// check them on the real server.
@MainActor
struct ServerContractTests {
    @Test(arguments: ServerKind.available)
    func anUploadReplacesTheRowAndADownloadGetsTheRowsThatChanged(_ kind: ServerKind) async throws {
        let account = try await kind.account()
        let server = account.server
        var bello = dog(in: account.pack)
        try await server.upload([bello])
        #expect(try await server.download(ServerDog.self, of: account.pack, changedSince: nil).map(\.row) == [bello])

        bello.name = "Bello II"
        bello.deletedAt = start
        try await server.upload([bello])

        let rows = try await server.download(ServerDog.self, of: account.pack, changedSince: nil)
        #expect(rows.map(\.row) == [bello])
        // A date in a filter has only milliseconds, and Postgres keeps
        // microseconds, so a download asks from a moment before the change,
        // as the overlap of `PackDownload` does.
        let changedAt = try #require(rows.first).changedAt
        #expect(try await server.download(ServerDog.self, of: account.pack, changedSince: changedAt - 1).map(\.row) == [bello])
        #expect(try await server.download(ServerDog.self, of: account.pack, changedSince: changedAt + 60).isEmpty)
    }

    @Test(arguments: ServerKind.available)
    func aRowOfAnotherPackIsRefusedAndAnotherPackDownloadsNothing(_ kind: ServerKind) async throws {
        let account = try await kind.account()
        let otherPack = UUID()

        await #expect(throws: RowRefused.self) { try await account.server.upload([dog(in: otherPack)]) }

        #expect(try await account.server.download(ServerDog.self, of: otherPack, changedSince: nil).isEmpty)
    }

    @Test(arguments: ServerKind.available)
    func aRowThatPointsToARowThatTheServerDoesNotHaveIsRefused(_ kind: ServerKind) async throws {
        let account = try await kind.account()
        let walkDog = ServerWalkDog(id: UUID(), packID: account.pack, walkID: UUID(), dogID: UUID(), deletedAt: nil)
        let record = ServerCompletedArea(
            id: UUID(), packID: account.pack, dogID: UUID(), area: 243, completedAt: start, deletedAt: nil)

        await #expect(throws: RowRefused.self) { try await account.server.upload([walkDog]) }
        await #expect(throws: RowRefused.self) { try await account.server.upload([record]) }

        #expect(try await account.server.download(ServerWalkDog.self, of: account.pack, changedSince: nil).isEmpty)
        #expect(try await account.server.download(ServerCompletedArea.self, of: account.pack, changedSince: nil).isEmpty)
    }

    @Test(arguments: ServerKind.available)
    func theEarliestRecordOfEachDogAndGoalStays(_ kind: ServerKind) async throws {
        let account = try await kind.account()
        let bello = dog(in: account.pack)
        try await account.server.upload([bello])
        let pack = account.pack

        try await checkEarliestStays(on: account) { id, date in
            ServerCompletedArea(id: id, packID: pack, dogID: bello.id, area: 243, completedAt: date, deletedAt: nil)
        }
        try await checkEarliestStays(on: account) { id, date in
            ServerCompletedStreet(
                id: id, packID: pack, dogID: bello.id, area: 243, street: "Zürcherstrasse", completedAt: date,
                deletedAt: nil)
        }
        try await checkEarliestStays(on: account) { id, date in
            ServerAreaStep(id: id, packID: pack, dogID: bello.id, area: 243, step: 25, reachedAt: date, deletedAt: nil)
        }
        try await checkEarliestStays(on: account) { id, date in
            ServerCompletedRing(
                id: id, packID: pack, dogID: bello.id, ring: 3, radiusMetres: 490, centreLatitude: 47.4,
                centreLongitude: 8.4, completedAt: date, deletedAt: nil)
        }
    }

    @Test(arguments: ServerKind.available)
    func theServerKeepsOneSetOfWeeklyGoalsForEachDogAndWeekWithOneSwap(_ kind: ServerKind) async throws {
        let account = try await kind.account()
        let server = account.server
        let bello = dog(in: account.pack)
        try await server.upload([bello])
        let weekStart = WeekCalendar.week(containing: start).start
        var set = ServerGoalSet(
            id: UUID(), packID: account.pack, dogID: bello.id, weekStart: weekStart,
            slots: [
                GoalSlotColumns(goal: GoalColumns(kind: "new_length", target: 1_000), finishedAt: start + 120),
                GoalSlotColumns(goal: GoalColumns(kind: "new_area"), finishedAt: nil),
                GoalSlotColumns(goal: GoalColumns(kind: "distance", target: 8_000), finishedAt: nil),
            ],
            swappedSlot: nil)
        try await server.upload([set])

        var second = set
        second.id = UUID()
        await #expect(throws: RowRefused.self) { try await server.upload([second]) }
        var nextWeek = set
        nextWeek.weekStart = WeekCalendar.weekStart(weekStart, movedBy: 1)
        await #expect(throws: RowRefused.self) { try await server.upload([nextWeek]) }

        set.slots[0].finishedAt = start + 600
        try await server.upload([set])
        set.slots[0].finishedAt = start + 60
        try await server.upload([set])
        #expect(try await storedSet(on: account).slots[0].finishedAt == start + 60)

        set.slots[1] = GoalSlotColumns(goal: GoalColumns(kind: "distance", target: 5_000), finishedAt: nil)
        set.swappedSlot = 2
        try await server.upload([set])
        var secondSwap = set
        secondSwap.slots[2] = GoalSlotColumns(goal: GoalColumns(kind: "new_area"), finishedAt: nil)
        secondSwap.swappedSlot = 3
        await #expect(throws: RowRefused.self) { try await server.upload([secondSwap]) }

        #expect(try await storedSet(on: account) == set)
    }

    @Test(arguments: ServerKind.available)
    func aDogKeepsItsPhotoPathWhenStorageDoesNotHaveTheNewPhoto(_ kind: ServerKind) async throws {
        let account = try await kind.account()
        let server = account.server
        var bello = dog(in: account.pack)
        let photo = ServerFile.dogPhoto(dog: bello.id, pack: account.pack, hash: "photo1")
        try await server.uploadFile(Data([0xFF, 0xD8]), to: photo)
        bello.photoPath = photo.path
        try await server.upload([bello])

        var withoutFile = bello
        withoutFile.photoPath = ServerFile.dogPhoto(dog: bello.id, pack: account.pack, hash: "photo2").path
        try await server.upload([withoutFile])
        #expect(try await storedDog(on: account).photoPath == photo.path)

        let newPhoto = ServerFile.dogPhoto(dog: bello.id, pack: account.pack, hash: "photo3")
        try await server.uploadFile(Data([0xFF, 0xD9]), to: newPhoto)
        bello.photoPath = newPhoto.path
        try await server.upload([bello])
        #expect(try await storedDog(on: account).photoPath == newPhoto.path)
    }

    @Test(arguments: ServerKind.available)
    func aWalkWithoutAMemberNameGetsTheNameOfTheMemberWhoUploadsIt(_ kind: ServerKind) async throws {
        let account = try await kind.account()
        try await account.server.renameMember(to: "Anna")
        let unnamed = walk(in: account.pack, memberName: "")
        let named = walk(in: account.pack, memberName: "Ben")

        try await account.server.upload([unnamed, named])

        let walks = try await account.server.download(ServerWalk.self, of: account.pack, changedSince: nil)
        let names = Dictionary(uniqueKeysWithValues: walks.map { ($0.row.id, $0.row.memberName) })
        #expect(names == [unnamed.id: "Anna", named.id: "Ben"])
    }

    /// The URL session keeps a downloaded file, so a file that the test
    /// expects to be missing was never downloaded before.
    @Test(arguments: ServerKind.available)
    func aFileUploadsDownloadsAndLeavesStorage(_ kind: ServerKind) async throws {
        let account = try await kind.account()
        let server = account.server
        let kept = ServerFile.track(walk: UUID(), pack: account.pack)
        let deleted = ServerFile.track(walk: UUID(), pack: account.pack)
        let deletedWithPack = ServerFile.track(walk: UUID(), pack: account.pack)
        for file in [kept, deleted, deletedWithPack] {
            try await server.uploadFile(Data(file.path.utf8), to: file)
        }

        #expect(try await server.downloadFile(kept) == Data(kept.path.utf8))
        try await server.deleteFile(deleted)
        await #expect(throws: FileMissing.self) { try await server.downloadFile(deleted) }
        try await server.deleteFile(deleted)
        try await server.deleteFiles(ofPack: account.pack)
        await #expect(throws: FileMissing.self) { try await server.downloadFile(deletedWithPack) }

        let otherPack = ServerFile.track(walk: UUID(), pack: UUID())
        await #expect(throws: (any Error).self) { try await server.uploadFile(Data([1]), to: otherPack) }
    }

    @Test(arguments: ServerKind.available)
    func aPackIsMadeOnceAndAChangeWithoutAHomeBaseKeepsIt(_ kind: ServerKind) async throws {
        let account = try await kind.account()
        let server = account.server
        let home = HomeBase(latitude: 47.4, longitude: 8.4)

        try await server.createPack(id: account.pack, name: "", createdAt: start)
        await #expect(throws: (any Error).self) {
            try await server.createPack(id: UUID(), name: "", createdAt: start)
        }
        try await server.updatePack(id: account.pack, with: ServerPackChange(
            name: "Bellos Rudel", homeLatitude: home.latitude, homeLongitude: home.longitude, homeSetAt: start))
        try await server.updatePack(id: account.pack, with: ServerPackChange(name: "Annas Rudel"))
        try await server.renameMember(to: "Anna")

        let pack = try #require(try await server.pack(id: account.pack))
        #expect(pack.name == "Annas Rudel")
        #expect(pack.homeBase == home)
        #expect(pack.homeSetAt == start)
        #expect(try await server.pack(id: UUID()) == nil)
        #expect(try await server.member() == ServerMember(name: "Anna", packID: account.pack))
    }

    /// Uploads a record, an earlier record and a later record with the same
    /// dog and goal. Only the earlier record stays without a deletion time.
    private func checkEarliestStays<Row: SyncedRow & Equatable>(
        on account: ServerAccount, record: (UUID, Date) -> Row
    ) async throws {
        let first = record(UUID(), start)
        let earlier = record(UUID(), start - 60)
        let later = record(UUID(), start + 60)
        for row in [first, earlier, later] {
            try await account.server.upload([row])
        }

        let rows = try await account.server.download(Row.self, of: account.pack, changedSince: nil).map(\.row)
        #expect(Set(rows.map(\.id)) == [first.id, earlier.id, later.id], "\(Row.table)")
        #expect(rows.filter { $0.deletedAt == nil }.map(\.id) == [earlier.id], "\(Row.table)")
    }

    private func storedSet(on account: ServerAccount) async throws -> ServerGoalSet {
        try #require(try await account.server.download(ServerGoalSet.self, of: account.pack, changedSince: nil).first)
            .row
    }

    private func storedDog(on account: ServerAccount) async throws -> ServerDog {
        try #require(try await account.server.download(ServerDog.self, of: account.pack, changedSince: nil).first).row
    }

    private func dog(in pack: UUID) -> ServerDog {
        ServerDog(
            id: UUID(), packID: pack, name: "Bello", photoPath: nil, retiredAt: nil, retirementReason: "",
            deletedAt: nil)
    }

    private func walk(in pack: UUID, memberName: String) -> ServerWalk {
        ServerWalk(
            id: UUID(), packID: pack, startedAt: start, endedAt: start + 3_600, trackPath: nil, distanceMetres: 1_200,
            distanceVersion: 1, continuedAt: nil, deviceID: "device", memberName: memberName, deletedAt: nil)
    }
}

/// A server that the contract tests run against.
nonisolated enum ServerKind: String, CaseIterable, Sendable {
    case fake
    case localSupabase

    /// The fake, and the local Supabase when it runs.
    static var available: [ServerKind] {
        LocalSupabase.isRunning ? allCases : [.fake]
    }

    /// A new account that has signed in and made its own pack.
    @MainActor
    func account() async throws -> ServerAccount {
        let server: any Server
        switch self {
        case .fake:
            let fake = FakeServer()
            try await fake.signIn(appleIDToken: "token", nonce: "nonce")
            server = fake
        case .localSupabase:
            server = try await LocalSupabase.signedInServer()
        }
        let pack = UUID()
        try await server.createPack(id: pack, name: "", createdAt: start)
        return ServerAccount(server: server, pack: pack)
    }
}

/// An account that has signed in, with its own pack.
struct ServerAccount {
    let server: any Server
    let pack: UUID
}

private let start = Date(timeIntervalSince1970: 1_790_000_000)
