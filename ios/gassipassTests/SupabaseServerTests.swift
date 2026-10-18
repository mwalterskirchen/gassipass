//
//  SupabaseServerTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Foundation
import Supabase
import SwiftData
import Testing
@testable import gassipass

/// The Supabase client of the app. Without an account it makes no request.
@MainActor
struct SupabaseServerTests {
    @Test func aPersonWithoutAnAccountMakesNoRequest() async throws {
        let container = try LocalStore.inMemory()
        try Packs(context: container.mainContext).addDog(named: "Bello")
        let server = SupabaseServer(client: LocalSupabase.client(session: RequestCounter.session))

        let account = Account(server: server, context: container.mainContext, defaults: emptyDefaults())
        await account.upload()

        #expect(!account.isSignedIn)
        #expect(RequestCounter.count == 0)
    }
}

/// The Supabase client of the app against the local Supabase of
/// `supabase start`. The tests do not run when it does not run.
@MainActor
@Suite(.enabled(if: LocalSupabase.isRunning, "The local Supabase does not run. Start it with `supabase start`."))
struct LocalSupabaseServerTests {
    @Test func theMemberAndThePackUploadAndASecondAccountCannotReadThePack() async throws {
        let anna = try await LocalSupabase.signedInServer()
        let ben = try await LocalSupabase.signedInServer()
        let packID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_790_000_000)

        try await anna.renameMember(to: "Anna")
        try await anna.createPack(id: packID, name: "Bellos Rudel", createdAt: createdAt)
        try await anna.createPack(id: packID, name: "Bellos Rudel", createdAt: createdAt)
        try await anna.updatePack(id: packID, with: ServerPackChange(name: "Annas Rudel"))
        try await ben.updatePack(id: packID, with: ServerPackChange(name: "Bens Rudel"))

        #expect(try await anna.member() == ServerMember(name: "Anna", packID: packID))
        #expect(try await ben.member() == ServerMember(name: "", packID: nil))
        let annasPacks: [ServerPack] = try await anna.client.from("packs").select().execute().value
        let bensPacks: [ServerPack] = try await ben.client.from("packs").select().execute().value
        #expect(annasPacks == [ServerPack(id: packID, name: "Annas Rudel", createdAt: createdAt)])
        #expect(bensPacks.isEmpty)
    }

    @Test func theHomeBaseAndTheRingStampsUploadAndASecondAccountCannotReadThem() async throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let packs = Packs(context: context)
        let bello = try packs.addDog(named: "Bello")
        let pack = try #require(bello.pack)
        let home = HomeBase(latitude: 47.403_512, longitude: 8.400_127)
        try packs.setHomeBase(home, of: pack)
        let completedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let stamp = CompletedRing(
            dogID: bello.id, ring: Ring(number: 3, centre: home), completedAt: completedAt, context: context)
        try context.save()
        let anna = try await LocalSupabase.signedInServer()
        let account = Account(server: anna, context: context, defaults: emptyDefaults())

        await account.renameMember(to: "Anna")

        let annasPack = try #require(try await anna.pack(id: pack.id))
        #expect(annasPack.homeBase == home)
        #expect(try #require(annasPack.homeSetAt).isSameMillisecond(as: try #require(pack.homeSetAt)))
        let rings = try await anna.download(ServerCompletedRing.self, of: pack.id, changedSince: nil)
        #expect(rings.map(\.row) == [ServerCompletedRing(
            id: stamp.id, packID: pack.id, dogID: bello.id, ring: 3, radiusMetres: 500,
            centreLatitude: home.latitude, centreLongitude: home.longitude, completedAt: completedAt, deletedAt: nil)])
        #expect(account.waitingChanges == 0)

        let ben = try await LocalSupabase.signedInServer()
        #expect(try await ben.pack(id: pack.id) == nil)
        #expect(try await ben.download(ServerCompletedRing.self, of: pack.id, changedSince: nil).isEmpty)
    }

    @Test func theWeeklyGoalsUploadAndTheServerRefusesASecondSetForTheSameWeek() async throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let bello = try Packs(context: context).addDog(named: "Bello")
        let pack = try #require(bello.pack)
        let finishedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let weekStart = WeekCalendar.week(containing: finishedAt).start
        let set = WeeklyGoalSet(
            dog: bello.id, weekStart: weekStart,
            slots: [
                GoalSlot(goal: .distance(metres: 5_000), finishedAt: finishedAt),
                GoalSlot(goal: .street(Street.ID(area: 243, name: "Kirchweg")), finishedAt: nil),
                GoalSlot(goal: .areaStep(AreaStepID(area: 243, step: .completed)), finishedAt: nil),
            ],
            swappedSlot: 2)
        let stored = StoredGoalSet(set, context: context)
        try context.save()
        let anna = try await LocalSupabase.signedInServer()
        let account = Account(server: anna, context: context, defaults: emptyDefaults())

        await account.renameMember(to: "Anna")

        let sets = try await anna.download(ServerGoalSet.self, of: pack.id, changedSince: nil)
        #expect(sets.map(\.row.id) == [stored.id])
        #expect(sets.map(\.row.set) == [set])
        #expect(account.waitingChanges == 0)
        var second = ServerGoalSet(id: UUID(), packID: pack.id, set: set)
        second.set?.swappedSlot = nil
        await #expect(throws: RowRefused.self) { try await anna.upload([second]) }

        let ben = try await LocalSupabase.signedInServer()
        #expect(try await ben.download(ServerGoalSet.self, of: pack.id, changedSince: nil).isEmpty)
    }

    @Test func eachKindOfRowUploadsAndASecondAccountCannotReadIt() async throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let packs = Packs(context: context)
        let photo = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let bello = try packs.addDog(named: "Bello", photoData: photo)
        let pack = try #require(bello.pack)
        let started = Date(timeIntervalSince1970: 1_790_000_000)
        let walk = Walk(startedAt: started, dogs: [bello], context: context)
        walk.store(Track(points: [
            TrackPoint(latitude: 47.4, longitude: 8.4, timestamp: started, horizontalAccuracy: 5),
        ]))
        walk.endedAt = started + 3_600
        let area = CompletedArea(dog: bello, area: 243, completedAt: started, context: context)
        let street = CompletedStreet(
            dog: bello, street: Street.ID(area: 243, name: "Zürcherstrasse"), completedAt: started, context: context)
        let step = AreaStep(dog: bello, area: 243, step: .quarter, reachedAt: started, context: context)
        try context.save()
        let anna = try await LocalSupabase.signedInServer()
        let account = Account(server: anna, context: context, defaults: emptyDefaults())

        await account.renameMember(to: "Anna")

        let dogs: [LocalSupabase.DogRow] = try await anna.client.from("dogs").select().execute().value
        #expect(dogs == [LocalSupabase.DogRow(
            id: bello.id, packID: pack.id, name: "Bello", photoPath: ServerFile.dogPhoto(dog: bello.id, pack: pack.id, data: photo).path,
            retiredAt: nil, deletedAt: nil)])
        let walks: [LocalSupabase.WalkRow] = try await anna.client.from("walks").select().execute().value
        // A walk with an empty member name gets the name of the pack owner.
        #expect(walks == [LocalSupabase.WalkRow(
            id: walk.id, packID: pack.id, startedAt: started, trackPath: ServerFile.track(walk: walk.id, pack: pack.id).path,
            memberName: "Anna", deletedAt: nil)])
        let walkDogs: [LocalSupabase.WalkDogRow] = try await anna.client.from("walk_dogs").select().execute().value
        #expect(walkDogs.map(\.dogID) == [bello.id])
        let areas: [LocalSupabase.RecordRow] = try await anna.client.from("completed_areas").select().execute().value
        #expect(areas.map(\.id) == [area.id])
        let streets: [LocalSupabase.RecordRow] = try await anna.client.from("completed_streets").select().execute().value
        #expect(streets.map(\.id) == [street.id])
        let steps = try await anna.download(ServerAreaStep.self, of: pack.id, changedSince: nil)
        #expect(steps.map(\.row) == [ServerAreaStep(
            id: step.id, packID: pack.id, dogID: bello.id, area: 243, step: 25, reachedAt: started, deletedAt: nil)])
        let storedPhoto = try await anna.client.storage.from("dog-photos")
            .download(path: ServerFile.dogPhoto(dog: bello.id, pack: pack.id, data: photo).path)
        #expect(storedPhoto == photo)
        let storedTrack = try await anna.client.storage.from("tracks")
            .download(path: ServerFile.track(walk: walk.id, pack: pack.id).path)
        #expect(storedTrack == walk.trackData)
        #expect(account.waitingChanges == 0)

        let ben = try await LocalSupabase.signedInServer()
        let bensDogs: [LocalSupabase.DogRow] = try await ben.client.from("dogs").select().execute().value
        let bensWalks: [LocalSupabase.WalkRow] = try await ben.client.from("walks").select().execute().value
        #expect(bensDogs.isEmpty)
        #expect(bensWalks.isEmpty)
        await #expect(throws: (any Error).self) {
            try await ben.client.storage.from("tracks").download(path: ServerFile.track(walk: walk.id, pack: pack.id).path)
        }
    }

    @Test func aDeletedWalkAChangeToItsDogsAndARenamedRetiredDogUpload() async throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let packs = Packs(context: context)
        let bello = try packs.addDog(named: "Bello")
        let luna = try packs.addDog(named: "Luna")
        let walk = Walk(startedAt: .now - 3_600, dogs: [bello], context: context)
        walk.store(Track())
        walk.endedAt = .now
        let deleted = Walk(startedAt: .now - 3_600, dogs: [bello], context: context)
        deleted.store(Track())
        deleted.endedAt = .now
        try context.save()
        let anna = try await LocalSupabase.signedInServer()
        let account = Account(server: anna, context: context, defaults: emptyDefaults())
        await account.upload()

        bello.name = "Bello II"
        bello.retire(on: Date(timeIntervalSince1970: 1_790_000_000), reason: "Old age")
        bello.noteChange()
        walk.changeDogs(to: [luna])
        deleted.markDeleted()
        try context.save()
        await account.upload()

        let dog: LocalSupabase.DogRow = try await anna.client.from("dogs").select().eq("id", value: bello.id)
            .single().execute().value
        #expect(dog.name == "Bello II")
        #expect(dog.retiredAt == Date(timeIntervalSince1970: 1_790_000_000))
        let walkDogs: [LocalSupabase.WalkDogRow] = try await anna.client.from("walk_dogs").select()
            .eq("walk_id", value: walk.id).is("deleted_at", value: nil).execute().value
        #expect(walkDogs.map(\.dogID) == [luna.id])
        let deletedRow: LocalSupabase.WalkRow = try await anna.client.from("walks").select().eq("id", value: deleted.id)
            .single().execute().value
        #expect(deletedRow.deletedAt != nil)
        #expect(account.waitingChanges == 0)
    }

    @Test func aRemovedPhotoLeavesStorage() async throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let bello = try Packs(context: context).addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        let pack = try #require(bello.pack)
        let anna = try await LocalSupabase.signedInServer()
        let account = Account(server: anna, context: context, defaults: emptyDefaults())
        await account.upload()

        bello.photoData = nil
        bello.noteChange()
        try context.save()
        await account.upload()

        let dog: LocalSupabase.DogRow = try await anna.client.from("dogs").select().eq("id", value: bello.id)
            .single().execute().value
        #expect(dog.photoPath == nil)
        let photos = try await anna.client.storage.from("dog-photos").list(path: pack.id.uuidString.lowercased())
        #expect(photos.isEmpty)
        #expect(account.waitingChanges == 0)
    }

    /// A dog name has at most 100 characters on the server.
    @Test func aDogThatTheServerRefusesWaitsAndTheOtherDogUploads() async throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let packs = Packs(context: context)
        let refused = try packs.addDog(named: String(repeating: "a", count: 101))
        let bello = try packs.addDog(named: "Bello")
        let anna = try await LocalSupabase.signedInServer()
        let account = Account(server: anna, context: context, defaults: emptyDefaults())

        await account.upload()

        let dogs: [LocalSupabase.DogRow] = try await anna.client.from("dogs").select().execute().value
        #expect(dogs.map(\.id) == [bello.id])
        #expect(refused.isWaitingToUpload)
        #expect(account.waitingChanges == 1)
    }

    /// Two phones can each store a record for the same dog and area.
    @Test func ofTwoCompletedRecordsForTheSameDogAndAreaOnlyTheEarliestStays() async throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let bello = try Packs(context: context).addDog(named: "Bello")
        let early = CompletedArea(dog: bello, area: 243, completedAt: Date(timeIntervalSince1970: 1_790_000_000), context: context)
        _ = CompletedArea(dog: bello, area: 243, completedAt: Date(timeIntervalSince1970: 1_790_100_000), context: context)
        try context.save()
        let anna = try await LocalSupabase.signedInServer()
        let account = Account(server: anna, context: context, defaults: emptyDefaults())

        await account.upload()

        let records: [LocalSupabase.RecordRow] = try await anna.client.from("completed_areas").select()
            .is("deleted_at", value: nil).execute().value
        #expect(records.map(\.id) == [early.id])
    }

    @Test func aWalkWhoseTrackFailedToUploadUploadsWithTheNextUpload() async throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let bello = try Packs(context: context).addDog(named: "Bello")
        let walk = Walk(startedAt: .now - 3_600, dogs: [bello], context: context)
        walk.store(Track())
        walk.endedAt = .now
        try context.save()
        let anna = try await LocalSupabase.signedInServer()
        let server = FailingOnceServer(anna)
        let account = Account(server: server, context: context, defaults: emptyDefaults())

        await account.upload()
        let walksAfterFailure: [LocalSupabase.WalkRow] = try await anna.client.from("walks").select().execute().value
        let waitingAfterFailure = account.waitingChanges
        await account.upload()

        let walks: [LocalSupabase.WalkRow] = try await anna.client.from("walks").select().execute().value
        let walkDogs: [LocalSupabase.WalkDogRow] = try await anna.client.from("walk_dogs").select().execute().value
        #expect(walksAfterFailure.isEmpty)
        #expect(waitingAfterFailure == 2)
        #expect(walks.map(\.id) == [walk.id])
        #expect(walkDogs.map(\.dogID) == [bello.id])
        #expect(account.waitingChanges == 0)
    }
}

/// The download of the pack on a second phone of the same account, against
/// the local Supabase of `supabase start`.
@MainActor
@Suite(.enabled(if: LocalSupabase.isRunning, "The local Supabase does not run. Start it with `supabase start`."))
struct LocalSupabaseDownloadTests {
    typealias Phone = gassipassTests.Phone<SupabaseServer>

    let start = Date(timeIntervalSince1970: 1_790_000_000)
    /// The two phones of a new account. The first phone has signed in.
    func phones() async throws -> (first: Phone, second: Phone) {
        let email = try await LocalSupabase.newAccount()
        let first = try Phone(server: try await LocalSupabase.signedInServer(email: email))
        let second = try Phone(server: try await LocalSupabase.signedInServer(email: email))
        return (first, second)
    }

    @Test func aSecondPhoneGetsThePackWithItsDogsWalksAndRecords() async throws {
        let (first, second) = try await phones()
        let photo = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let bello = try first.packs.addDog(named: "Bello", photoData: photo)
        let pack = try #require(bello.pack)
        try first.packs.rename(pack, to: "Bellos Rudel")
        let walk = try first.recordWalk(startedAt: start, dogs: [bello])
        let area = CompletedArea(dog: bello, area: 243, completedAt: start, context: first.context)
        let street = CompletedStreet(
            dog: bello, street: Street.ID(area: 243, name: "Zürcherstrasse"), completedAt: start,
            context: first.context)
        let step = AreaStep(dog: bello, area: 243, step: .entry, reachedAt: start, context: first.context)
        try first.context.save()
        await first.account.renameMember(to: "Anna")

        await second.account.refresh()

        let secondPack = try #require(try second.packs.all().first)
        #expect(secondPack.id == pack.id)
        #expect(secondPack.name == "Bellos Rudel")
        let dogs = try second.context.fetch(Dog.all())
        #expect(dogs.map(\.id) == [bello.id])
        #expect(dogs.first?.photoData == photo)
        let secondWalk = try second.walk(walk.id)
        #expect(secondWalk.trackData == walk.trackData)
        #expect(secondWalk.endedAt == walk.endedAt)
        #expect(secondWalk.memberName == "Anna")
        #expect(secondWalk.dogs.map(\.id) == [bello.id])
        #expect(try second.context.fetchAll(CompletedArea.self).map(\.id) == [area.id])
        #expect(try second.context.fetchAll(CompletedStreet.self).map(\.id) == [street.id])
        #expect(try second.context.fetchAll(AreaStep.self).map(\.id) == [step.id])
        #expect(second.account.memberName == "Anna")
        #expect(second.account.waitingChanges == 0)
    }

    /// The second phone renames Bello before it downloads his new photo, so
    /// its upload names the photo that the first phone deleted. The trigger
    /// of the server keeps the new photo (#130).
    @Test func aNewPhotoStaysWhenAnotherPhoneChangesTheDogBeforeItsDownload() async throws {
        let (first, second) = try await phones()
        let bello = try first.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0x01]))
        await first.account.renameMember(to: "Anna")
        await second.account.refresh()
        bello.photoData = Data([0xFF, 0xD8, 0x02])
        bello.noteChange()
        try first.context.save()
        await first.account.upload()
        let secondBello = try second.dog(bello.id)
        secondBello.name = "Bello B"
        secondBello.noteChange()
        try second.context.save()

        await second.account.upload()
        await second.account.refresh()
        await first.account.refresh()

        for dog in [bello, secondBello] {
            #expect(dog.name == "Bello B")
            #expect(dog.photoData == Data([0xFF, 0xD8, 0x02]))
        }
    }

    /// A dog row can point to a photo that Storage does not have. The second
    /// phone stores the dog without it.
    @Test func aDogWhosePhotoIsMissingArrivesWithoutIt() async throws {
        let (first, second) = try await phones()
        let bello = try first.packs.addDog(named: "Bello")
        await first.account.renameMember(to: "Anna")
        let pack = try #require(bello.pack)
        let missing = ServerFile.dogPhoto(dog: UUID(), pack: pack.id, hash: "0000")
        try await first.server.client.from("dogs").insert(ServerDog(
            id: UUID(), packID: pack.id, name: "Luna", photoPath: missing.path, retiredAt: nil,
            retirementReason: "", deletedAt: nil)).execute()

        await #expect(throws: FileMissing.self) {
            try await second.server.downloadFile(missing)
        }
        await second.account.refresh()

        #expect(try second.dogs().map(\.name) == ["Bello", "Luna"])
        #expect(try second.dogs().allSatisfy { $0.photoData == nil })
        #expect(second.account.waitingChanges == 0)
    }

    @Test func aLaterWalkReachesTheSecondPhone() async throws {
        let (first, second) = try await phones()
        let bello = try first.packs.addDog(named: "Bello")
        try first.recordWalk(startedAt: start, dogs: [bello])
        await first.account.upload()
        await second.account.refresh()

        let later = try first.recordWalk(startedAt: start + 86_400, dogs: [bello])
        await first.account.upload()
        await second.account.refresh()

        #expect(try second.context.fetch(Walk.ended()).first?.id == later.id)
        #expect(try second.context.fetch(Walk.ended()).count == 2)
        #expect(try second.walk(later.id).trackData == later.trackData)
    }

    @Test func aDeletedWalkLeavesTheSecondPhone() async throws {
        let (first, second) = try await phones()
        let bello = try first.packs.addDog(named: "Bello")
        let walk = try first.recordWalk(startedAt: start, dogs: [bello])
        await first.account.upload()
        await second.account.refresh()

        walk.markDeleted()
        try first.context.save()
        await first.account.upload()
        await second.account.refresh()

        #expect(try second.context.fetch(Walk.ended()).isEmpty)
        #expect(try second.walk(walk.id).deletedAt != nil)
        #expect(try second.walk(walk.id).trackData == nil)
        #expect(second.account.waitingChanges == 0)
    }

    /// PostgREST gives at most 1000 rows for each request. The rows come
    /// from one request, so they all have the same time of change.
    @Test func aDownloadGetsMoreRowsThanOnePage() async throws {
        let (first, _) = try await phones()
        let bello = try first.packs.addDog(named: "Bello")
        let pack = try #require(bello.pack)
        await first.account.upload()
        let records = (1...1_001).map { area in
            ServerCompletedArea(
                id: UUID(), packID: pack.id, dogID: bello.id, area: area, completedAt: start, deletedAt: nil)
        }
        try await LocalSupabase.admin.from("completed_areas").insert(records, returning: .minimal).execute()

        let downloaded = try await first.server.download(ServerCompletedArea.self, of: pack.id, changedSince: nil)

        #expect(Set(downloaded.map(\.row.id)) == Set(records.map(\.id)))
        #expect(downloaded.count == 1_001)
    }
}

/// The invitation to a pack and the join, against the local Supabase.
@MainActor
@Suite(.enabled(if: LocalSupabase.isRunning, "The local Supabase does not run. Start it with `supabase start`."))
struct LocalSupabaseInvitationTests {
    typealias Phone = gassipassTests.Phone<SupabaseServer>

    let start = Date(timeIntervalSince1970: 1_790_000_000)
    /// The phone of Anna, whose pack with Bello has uploaded.
    func annasPhone() async throws -> Phone {
        let anna = try Phone(server: try await LocalSupabase.signedInServer())
        let bello = try anna.packs.addDog(named: "Bello")
        try anna.packs.rename(try #require(bello.pack), to: "Annas Rudel")
        await anna.account.renameMember(to: "Anna")
        await anna.account.refresh()
        return anna
    }

    @Test func aPersonInNoPackJoinsAndTheirWalkReachesThePackOwner() async throws {
        let anna = try await annasPhone()
        let ben = try Phone(server: try await LocalSupabase.signedInServer())
        await ben.account.renameMember(to: "Ben")
        let annasPack = try #require(try anna.packs.all().first)

        #expect(anna.account.isPackOwner)
        let link = try await anna.account.makeInvitationLink()
        let token = try #require(InvitationLink.token(in: link))
        let invitation = try await ben.account.checkInvitation(token: token)
        let state = try await ben.account.join(token: token)

        #expect(invitation == Invitation(
            state: .open, packID: annasPack.id, packName: "Annas Rudel", packOwnerName: "Anna"))
        #expect(state == .joined)
        let bensPack = try #require(try ben.packs.all().first)
        #expect(bensPack.id == annasPack.id)
        let bello = try #require(bensPack.dogs?.first)
        #expect(bello.name == "Bello")
        #expect(ben.account.packMembers.map(\.name) == ["Anna", "Ben"])
        #expect(ben.account.packMembers.map(\.isPackOwner) == [true, false])
        #expect(ben.account.packMembers.map(\.isThisPerson) == [false, true])
        #expect(!ben.account.isPackOwner)

        // The current walk stores the name of the member who records it.
        let walk = try ben.recordWalk(startedAt: start, dogs: [bello])
        walk.memberName = ben.account.memberName
        try ben.context.save()
        await ben.account.upload()
        await anna.account.refresh()

        let annasWalk = try anna.walk(walk.id)
        #expect(annasWalk.memberName == "Ben")
        #expect(annasWalk.dogs.map(\.name) == ["Bello"])
        #expect(anna.account.packMembers.map(\.name) == ["Anna", "Ben"])
    }

    @Test func aUsedInvitationJoinsNobodyAndThePackOwnerIsAMemberAlready() async throws {
        let anna = try await annasPhone()
        let ben = try Phone(server: try await LocalSupabase.signedInServer())
        let carl = try await LocalSupabase.signedInServer()
        let token = try #require(InvitationLink.token(in: try await anna.account.makeInvitationLink()))

        #expect(try await anna.account.checkInvitation(token: token).state == .member)
        #expect(try await ben.account.join(token: token) == .joined)
        #expect(try await carl.checkInvitation(token: token).state == .used)
        #expect(try await carl.joinPack(token: token) == .used)
        #expect(try await carl.member().packID == nil)
        #expect(try await carl.checkInvitation(token: "unknown").state == .unknown)
    }

    /// Ben leaves the pack of Anna, and Anna removes Carl. Their phones keep
    /// nothing of the pack, and the walk of Ben stays with Bello.
    @Test func aMemberLeavesAndThePackOwnerRemovesAMember() async throws {
        let anna = try await annasPhone()
        let ben = try Phone(server: try await LocalSupabase.signedInServer())
        let carl = try Phone(server: try await LocalSupabase.signedInServer())
        await ben.account.renameMember(to: "Ben")
        await carl.account.renameMember(to: "Carl")
        for phone in [ben, carl] {
            let token = try #require(InvitationLink.token(in: try await anna.account.makeInvitationLink()))
            #expect(try await phone.account.join(token: token) == .joined)
        }
        let bello = try #require(try ben.context.fetch(Dog.all()).first)
        let walk = try ben.recordWalk(startedAt: start, dogs: [bello])
        walk.memberName = ben.account.memberName
        try ben.context.save()
        await anna.account.refresh()
        #expect(!ben.account.isPackOwner)
        #expect(ben.account.canLeavePack)
        #expect(!anna.account.canLeavePack)

        try await ben.account.leavePack()
        let carlAsMember = try #require(anna.account.packMembers.first { $0.name == "Carl" })
        try await anna.account.removeMember(carlAsMember)
        await carl.account.refresh()
        await anna.account.refresh()

        for phone in [ben, carl] {
            #expect(try phone.context.fetchAll(Pack.self).isEmpty)
            #expect(try phone.context.fetchAll(Dog.self).isEmpty)
            #expect(try phone.context.fetchAll(Walk.self).isEmpty)
            #expect(phone.account.packMembers.isEmpty)
            #expect(try await phone.server.member().packID == nil)
        }
        #expect(anna.account.packMembers.map(\.name) == ["Anna"])
        let annasWalk = try anna.walk(walk.id)
        #expect(annasWalk.memberName == "Ben")
        #expect(annasWalk.dogs.map(\.name) == ["Bello"])
        await #expect(throws: (any Error).self) {
            try await anna.account.leavePack()
        }
    }

    /// The only member of a pack joins, and brings their dogs (ADR 0005). The
    /// second phone of the person has uploaded a walk that the first phone
    /// has not downloaded. It also has a later completed record for the same
    /// dog and area, which has not uploaded yet.
    @Test func theOnlyMemberOfAPackBringsTheirDogsToThePackOwnerAndToTheirSecondPhone() async throws {
        let anna = try await annasPhone()
        let email = try await LocalSupabase.newAccount()
        let ben = try Phone(server: try await LocalSupabase.signedInServer(email: email))
        let bensSecond = try Phone(server: try await LocalSupabase.signedInServer(email: email))
        let photo = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let luna = try ben.packs.addDog(named: "Luna", photoData: photo)
        let bensPack = try #require(luna.pack)
        let walk = try ben.recordWalk(startedAt: start, dogs: [luna])
        let early = CompletedArea(dog: luna, area: 243, completedAt: start, context: ben.context)
        try ben.context.save()
        await ben.account.refresh()
        await bensSecond.account.refresh()
        let secondLuna = try #require(try bensSecond.context.fetch(Dog.all()).first)
        let secondWalk = try bensSecond.recordWalk(startedAt: start + 7_200, dogs: [secondLuna])
        await bensSecond.account.upload()
        let late = CompletedArea(
            dog: secondLuna, area: 243, completedAt: start + 86_400, context: bensSecond.context)
        try bensSecond.context.save()
        let token = try #require(InvitationLink.token(in: try await anna.account.makeInvitationLink()))

        let invitation = try await ben.account.checkInvitation(token: token)
        let state = try await ben.account.join(token: token)
        await anna.account.refresh()
        await bensSecond.account.refresh()

        #expect(invitation.state == .open)
        #expect(state == .joined)
        let annasPack = try #require(try anna.packs.all().first)
        #expect(try ben.context.fetchAll(Pack.self).map(\.id) == [annasPack.id])
        #expect(try bensSecond.context.fetchAll(Pack.self).map(\.id) == [annasPack.id])
        #expect(try await ben.server.pack(id: bensPack.id) == nil)
        for phone in [anna, ben, bensSecond] {
            #expect(try phone.context.fetch(Dog.all()).map(\.name) == ["Bello", "Luna"])
        }
        let annasLuna = try #require(try anna.context.fetch(Dog.all()).first { $0.id == luna.id })
        #expect(annasLuna.photoData == photo)
        #expect(try anna.walk(walk.id).trackData == walk.trackData)
        #expect(try anna.walk(walk.id).dogs.map(\.id) == [luna.id])
        // The GPS tracks stay in the folder of the old pack, also the track
        // that the first phone of Ben never had.
        let walkRows = try await anna.server.download(ServerWalk.self, of: annasPack.id, changedSince: nil)
        #expect(walkRows.first { $0.row.id == secondWalk.id }?.row.trackPath
            == ServerFile.track(walk: secondWalk.id, pack: bensPack.id).path)
        #expect(try anna.walk(secondWalk.id).trackData == secondWalk.trackData)
        #expect(try ben.walk(secondWalk.id).trackData == secondWalk.trackData)
        #expect(secondWalk.trackData != nil)
        #expect(try anna.context.fetchAll(CompletedArea.self).map(\.id) == [early.id])
        let records: [LocalSupabase.RecordRow] = try await anna.server.client.from("completed_areas").select()
            .is("deleted_at", value: nil).execute().value
        #expect(records.map(\.id) == [early.id])
        #expect(late.deletedAt != nil)
        #expect(ben.account.waitingChanges == 0)
        #expect(bensSecond.account.waitingChanges == 0)
    }

    /// The files of a pack that moved stay in the folder of the old pack.
    /// The pack owner of the new pack got them with a download, and when she
    /// deletes the walk and removes the photo, they leave that folder (#127).
    @Test func aMemberOfTheNewPackDeletesTheFilesOfAMovedPackFromTheFolderOfTheOldPack() async throws {
        let anna = try await annasPhone()
        let ben = try Phone(server: try await LocalSupabase.signedInServer())
        let luna = try ben.packs.addDog(named: "Luna", photoData: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        let bensPack = try #require(luna.pack)
        let walk = try ben.recordWalk(startedAt: start, dogs: [luna])
        await ben.account.refresh()
        let token = try #require(InvitationLink.token(in: try await anna.account.makeInvitationLink()))
        #expect(try await ben.account.join(token: token) == .joined)
        await anna.account.refresh()
        let filesAfterJoin = try await LocalSupabase.files(ofPack: bensPack.id)

        try anna.walk(walk.id).markDeleted()
        let annasLuna = try anna.dog(luna.id)
        annasLuna.photoData = nil
        annasLuna.noteChange()
        try anna.context.save()
        await anna.account.upload()

        #expect(filesAfterJoin.count == 2)
        #expect(try await LocalSupabase.files(ofPack: bensPack.id).isEmpty)
        #expect(anna.account.waitingChanges == 0)
    }

    /// The account of Ben is in the pack of Anna already, and his second
    /// phone has a pack of its own from before the sign-in.
    @Test func aSignInWithAPackOnThePhoneMovesItsDogsIntoThePackOfTheAccountAfterAConfirmation() async throws {
        let anna = try await annasPhone()
        let email = try await LocalSupabase.newAccount()
        let ben = try Phone(server: try await LocalSupabase.signedInServer(email: email))
        let token = try #require(InvitationLink.token(in: try await anna.account.makeInvitationLink()))
        #expect(try await ben.account.join(token: token) == .joined)
        let bensSecond = try Phone(server: try await LocalSupabase.signedInServer(email: email))
        let max = try bensSecond.packs.addDog(named: "Max")
        let walk = try bensSecond.recordWalk(startedAt: start, dogs: [max])
        let annasPack = try #require(try anna.packs.all().first)

        await bensSecond.account.refresh()

        #expect(bensSecond.account.packOfAccount?.id == annasPack.id)
        let dogRows = try await anna.server.download(ServerDog.self, of: annasPack.id, changedSince: nil)
        #expect(dogRows.map(\.row.name) == ["Bello"])

        await bensSecond.account.moveDogsIntoPackOfAccount()
        await anna.account.refresh()

        #expect(bensSecond.account.packOfAccount == nil)
        #expect(try bensSecond.context.fetchAll(Pack.self).map(\.id) == [annasPack.id])
        #expect(try bensSecond.context.fetch(Dog.all()).map(\.name) == ["Bello", "Max"])
        #expect(try anna.context.fetch(Dog.all()).map(\.name) == ["Bello", "Max"])
        #expect(try anna.walk(walk.id).trackData == walk.trackData)
        #expect(bensSecond.account.waitingChanges == 0)
    }

    @Test func aMemberWhoIsNotThePackOwnerCannotInvite() async throws {
        let anna = try await annasPhone()
        let ben = try Phone(server: try await LocalSupabase.signedInServer())
        let token = try #require(InvitationLink.token(in: try await anna.account.makeInvitationLink()))
        _ = try await ben.account.join(token: token)

        await #expect(throws: PostgrestError.self) {
            try await ben.account.makeInvitationLink()
        }
    }
}

/// The deletion of an account, against the local Supabase (#107).
@MainActor
@Suite(.enabled(if: LocalSupabase.isRunning, "The local Supabase does not run. Start it with `supabase start`."))
struct LocalSupabaseAccountDeletionTests {
    typealias Phone = gassipassTests.Phone<SupabaseServer>

    let start = Date(timeIntervalSince1970: 1_790_000_000)
    @Test func thePackOwnerDeletesTheirAccountAndTheMemberWhoJoinedFirstBecomesThePackOwner() async throws {
        let anna = try Phone(server: try await LocalSupabase.signedInServer())
        let bello = try anna.packs.addDog(named: "Bello")
        await anna.account.renameMember(to: "Anna")
        let walk = try anna.recordWalk(startedAt: start, dogs: [bello])
        walk.memberName = anna.account.memberName
        try anna.context.save()
        await anna.account.refresh()
        let ben = try Phone(server: try await LocalSupabase.signedInServer())
        await ben.account.renameMember(to: "Ben")
        let carl = try await LocalSupabase.signedInServer()
        try await carl.renameMember(to: "Carl")
        for joining in [ben.server, carl] {
            let token = try #require(InvitationLink.token(in: try await anna.account.makeInvitationLink()))
            #expect(try await joining.joinPack(token: token) == .joined)
        }

        try await anna.account.deleteAccount()
        await ben.account.refresh()

        #expect(!anna.account.isSignedIn)
        #expect(try anna.packs.all().isEmpty)
        #expect(ben.account.isPackOwner)
        #expect(ben.account.packMembers.map(\.name) == ["Ben", "Carl"])
        #expect(ben.account.packMembers.map(\.isPackOwner) == [true, false])
        let carlsMembers = try await carl.packMembers()
        #expect(carlsMembers.map(\.name) == ["Ben", "Carl"])
        #expect(carlsMembers.map(\.isPackOwner) == [true, false])
        let bensWalk = try ben.walk(walk.id)
        #expect(bensWalk.memberName == "Anna")
        #expect(bensWalk.dogs.map(\.name) == ["Bello"])
    }

    @Test func theOnlyMemberDeletesTheirAccountAndNothingOfThePackStaysOnTheServer() async throws {
        let anna = try Phone(server: try await LocalSupabase.signedInServer())
        let accountID = try #require(anna.server.client.auth.currentUser?.id)
        let bello = try anna.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        let pack = try #require(bello.pack)
        try anna.recordWalk(startedAt: start, dogs: [bello])
        _ = CompletedArea(dog: bello, area: 243, completedAt: start, context: anna.context)
        try anna.context.save()
        await anna.account.refresh()
        #expect(try await LocalSupabase.files(ofPack: pack.id).count == 2)

        try await anna.account.deleteAccount()

        #expect(!anna.account.isSignedIn)
        #expect(!anna.server.isSignedIn)
        #expect(try anna.packs.all().isEmpty)
        #expect(try await LocalSupabase.files(ofPack: pack.id).isEmpty)
        for table in ["dogs", "walks", "walk_dogs", "completed_areas", "completed_streets", "invitations"] {
            let rows: [LocalSupabase.RecordRow] = try await LocalSupabase.admin.from(table).select("id")
                .eq("pack_id", value: pack.id).execute().value
            #expect(rows.isEmpty, "\(table)")
        }
        let packs: [LocalSupabase.RecordRow] = try await LocalSupabase.admin.from("packs").select("id")
            .eq("id", value: pack.id).execute().value
        #expect(packs.isEmpty)
        let members: [LocalSupabase.MemberRow] = try await LocalSupabase.admin.from("members").select("account_id")
            .eq("account_id", value: accountID).execute().value
        #expect(members.isEmpty)
    }
}

/// The real server, whose first file upload fails.
private final class FailingOnceServer: Server {
    private let server: any Server
    private var failsNextFileUpload = true

    init(_ server: any Server) {
        self.server = server
    }

    struct Failure: Error {}

    var isSignedIn: Bool { server.isSignedIn }

    func signIn(appleIDToken: String, nonce: String) async throws {
        try await server.signIn(appleIDToken: appleIDToken, nonce: nonce)
    }

    func signOut() async { await server.signOut() }
    func packsDeletedWithAccount() async throws -> [UUID] { try await server.packsDeletedWithAccount() }
    func deleteFiles(ofPack pack: UUID) async throws { try await server.deleteFiles(ofPack: pack) }
    func deleteAccount() async throws { try await server.deleteAccount() }
    func member() async throws -> ServerMember { try await server.member() }
    func renameMember(to name: String) async throws { try await server.renameMember(to: name) }

    func createPack(id: UUID, name: String, createdAt: Date) async throws {
        try await server.createPack(id: id, name: name, createdAt: createdAt)
    }

    func updatePack(id: UUID, with change: ServerPackChange) async throws {
        try await server.updatePack(id: id, with: change)
    }
    func upload<Row: ServerRow>(_ rows: [Row]) async throws { try await server.upload(rows) }

    func uploadFile(_ data: Data, to file: ServerFile) async throws {
        if failsNextFileUpload {
            failsNextFileUpload = false
            throw Failure()
        }
        try await server.uploadFile(data, to: file)
    }

    func deleteFile(_ file: ServerFile) async throws { try await server.deleteFile(file) }
    func pack(id: UUID) async throws -> ServerPack? { try await server.pack(id: id) }

    func download<Row: ServerRow>(
        _ type: Row.Type, of pack: UUID, changedSince date: Date?
    ) async throws -> [Downloaded<Row>] {
        try await server.download(type, of: pack, changedSince: date)
    }

    func downloadFile(_ file: ServerFile) async throws -> Data { try await server.downloadFile(file) }
    func packMembers() async throws -> [PackMember] { try await server.packMembers() }
    func createInvitation() async throws -> String { try await server.createInvitation() }
    func checkInvitation(token: String) async throws -> Invitation { try await server.checkInvitation(token: token) }
    func joinPack(token: String) async throws -> InvitationState { try await server.joinPack(token: token) }

    func hasMovedIntoPackOfAccount(pack: UUID) async throws -> Bool {
        try await server.hasMovedIntoPackOfAccount(pack: pack)
    }
    func leavePack() async throws { try await server.leavePack() }
    func removeMember(id: UUID) async throws { try await server.removeMember(id: id) }
    func hasLeftPack(_ pack: UUID) async throws -> Bool { try await server.hasLeftPack(pack) }
}

/// The local Supabase of `supabase start`, with the fixed keys that the
/// Supabase CLI gives every local project.
@MainActor
enum LocalSupabase {
    nonisolated static let url = URL(string: "http://127.0.0.1:54321")!
    nonisolated static let publishableKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
    nonisolated static let secretKey = "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz"

    nonisolated struct DogRow: Decodable, Equatable {
        var id: UUID
        var packID: UUID
        var name: String
        var photoPath: String?
        var retiredAt: Date?
        var deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, name
            case packID = "pack_id"
            case photoPath = "photo_path"
            case retiredAt = "retired_at"
            case deletedAt = "deleted_at"
        }
    }

    nonisolated struct WalkRow: Decodable, Equatable {
        var id: UUID
        var packID: UUID
        var startedAt: Date
        var trackPath: String?
        var memberName: String
        var deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case packID = "pack_id"
            case startedAt = "started_at"
            case trackPath = "track_path"
            case memberName = "member_name"
            case deletedAt = "deleted_at"
        }
    }

    nonisolated struct WalkDogRow: Decodable, Equatable {
        var dogID: UUID

        enum CodingKeys: String, CodingKey {
            case dogID = "dog_id"
        }
    }

    nonisolated struct MemberRow: Decodable, Equatable {
        var accountID: UUID

        enum CodingKeys: String, CodingKey {
            case accountID = "account_id"
        }
    }

    /// A completed record of an area or a street.
    nonisolated struct RecordRow: Decodable, Equatable {
        var id: UUID
    }

    /// Whether the local Supabase answers.
    nonisolated static var isRunning: Bool {
        var request = URLRequest(url: url.appending(path: "auth/v1/health"), timeoutInterval: 1)
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        let answered = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var isRunning = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            isRunning = (response as? HTTPURLResponse)?.statusCode == 200
            answered.signal()
        }.resume()
        answered.wait()
        return isRunning
    }

    /// A client that keeps its session in memory, not in the keychain.
    static func client(session: URLSession = .shared) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: url, supabaseKey: publishableKey,
            options: SupabaseClientOptions(
                auth: .init(storage: MemoryStorage(), emitLocalSessionAsInitialSession: true),
                global: .init(session: session)))
    }

    /// The server, signed in with a new account. Sign in with Apple needs a
    /// real Apple ID, so the account signs in with a password.
    static func signedInServer() async throws -> SupabaseServer {
        try await signedInServer(email: newAccount())
    }

    /// The server, signed in with the account, as on one more phone.
    static func signedInServer(email: String) async throws -> SupabaseServer {
        // Each client has its own session, so that no account gets a
        // response from the cache of another account.
        let client = client(session: URLSession(configuration: .ephemeral))
        try await client.auth.signIn(email: email, password: "password")
        return SupabaseServer(client: client)
    }

    /// The files in the folder of the pack in each bucket, as the admin sees
    /// them.
    static func files(ofPack pack: UUID) async throws -> [String] {
        var names: [String] = []
        for bucket in ServerFile.Bucket.allCases {
            let files = try await admin.storage.from(bucket.rawValue).list(path: ServerFile.folder(of: pack))
            names += files.map { "\(bucket.rawValue)/\($0.name)" }
        }
        return names
    }

    /// Makes a new account, and returns its email address.
    static func newAccount() async throws -> String {
        let email = "\(UUID().uuidString.lowercased())@example.com"
        _ = try await admin.auth.admin.createUser(
            attributes: AdminUserAttributes(email: email, emailConfirm: true, password: "password"))
        return email
    }

    /// A client with the secret key, which row-level security does not stop.
    /// It lives as long as the tests, because the SDK stops the app when a
    /// client is released during one of its requests.
    static let admin = SupabaseClient(
        supabaseURL: url, supabaseKey: secretKey,
        options: SupabaseClientOptions(auth: .init(storage: MemoryStorage(), autoRefreshToken: false)))
}

nonisolated private final class MemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()

    func store(key: String, value: Data) throws {
        lock.withLock { values[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func remove(key: String) throws {
        _ = lock.withLock { values.removeValue(forKey: key) }
    }
}

/// Counts the requests of its session, and answers none of them.
nonisolated final class RequestCounter: URLProtocol {
    nonisolated(unsafe) static var count = 0

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCounter.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.count += 1
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
