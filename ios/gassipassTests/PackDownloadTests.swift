//
//  PackDownloadTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 12.10.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The download of the pack on a second phone of the same account, through
/// the account, with a server in memory that both phones share.
@MainActor
struct PackDownloadTests {
    let server = ObservedServer(FakeServer())
    let first: Phone<ObservedServer<FakeServer>>
    let second: Phone<ObservedServer<FakeServer>>
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        first = try Phone(server: server)
        second = try Phone(server: server)
    }

    @Test func aSecondPhoneThatSignsInGetsThePackWithItsDogsWalksAndRecords() async throws {
        let photo = Data([0xFF, 0xD8, 0xFF])
        let bello = try first.packs.addDog(named: "Bello", photoData: photo)
        let luna = try first.packs.addDog(named: "Luna")
        luna.retire(on: start, reason: "Old age")
        let pack = try #require(bello.pack)
        try first.packs.rename(pack, to: "Bellos Rudel")
        let walk = try first.recordWalk(startedAt: start, dogs: [bello, luna], memberName: "Anna")
        let area = CompletedArea(dog: bello, area: 243, completedAt: start, context: first.context)
        let street = CompletedStreet(
            dog: bello, street: Street.ID(area: 243, name: "Zürcherstrasse"), completedAt: start,
            context: first.context)
        try first.context.save()
        try await first.signIn(givenName: "Anna")

        try await second.signIn()

        let secondPack = try #require(try second.packs.all().first)
        #expect(secondPack.id == pack.id)
        #expect(secondPack.name == "Bellos Rudel")
        #expect(secondPack.createdAt == pack.createdAt)
        let dogs = try second.dogs()
        #expect(dogs.map(\.id) == [bello.id, luna.id])
        #expect(dogs.map(\.name) == ["Bello", "Luna"])
        #expect(dogs.map(\.pack?.id) == [pack.id, pack.id])
        #expect(dogs[0].photoData == photo)
        #expect(dogs[1].retiredAt == start)
        #expect(dogs[1].retirementReason == "Old age")
        let walks = try second.walks()
        #expect(walks.map(\.id) == [walk.id])
        #expect(walks[0].startedAt == start)
        #expect(walks[0].endedAt == start + 3_600)
        #expect(walks[0].trackData == walk.trackData)
        #expect(walks[0].distanceMetres == walk.distanceMetres)
        #expect(walks[0].memberName == "Anna")
        #expect(Set(walks[0].dogs.map(\.id)) == [bello.id, luna.id])
        let records = dogs[0].completedAreaRecords
        #expect(records == [CompletedRecord(dog: bello.id, goal: 243, date: start)])
        #expect(dogs[0].completedStreetRecords == [
            CompletedRecord(dog: bello.id, goal: street.streetID, date: start),
        ])
        #expect(try second.context.fetchAll(CompletedArea.self).map(\.id) == [area.id])
        #expect(second.account.waitingChanges == 0)
        #expect(!second.context.hasChanges)
    }

    @Test func aSecondPhoneGetsTheHomeBaseAndTheRingStamps() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        let pack = try #require(bello.pack)
        let home = HomeBase(latitude: 47.4, longitude: 8.4)
        try first.packs.setHomeBase(home, of: pack)
        let stamp = CompletedRing(
            dogID: bello.id, ring: Ring(number: 1, centre: home), completedAt: start, context: first.context)
        try first.context.save()
        try await first.signIn(givenName: "Anna")

        try await second.signIn()

        let secondPack = try #require(try second.packs.all().first)
        #expect(secondPack.homeBase == home)
        let stamps = try second.context.fetchAll(CompletedRing.self)
        #expect(stamps.map(\.id) == [stamp.id])
        #expect(stamps.map(\.record) == [CompletedRecord(dog: bello.id, goal: Ring(number: 1, centre: home), date: start)])
        #expect(stamps.allSatisfy { !$0.isWaitingToUpload })
        #expect(second.account.waitingChanges == 0)
        #expect(!second.context.hasChanges)
    }

    private func goalSet(of dog: Dog, _ goals: [WeeklyGoal], finishedAt: Date? = nil) -> WeeklyGoalSet {
        WeeklyGoalSet(
            dog: dog.id, weekStart: WeekCalendar.week(containing: start).start,
            slots: goals.map { GoalSlot(goal: $0, finishedAt: finishedAt) }, swappedSlot: nil)
    }

    @Test func aSecondPhoneGetsTheWeeklyGoals() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        let set = goalSet(of: bello, [.refresh(metres: 1_000), .ring(2), .newArea], finishedAt: start)
        let stored = StoredGoalSet(set, context: first.context)
        try first.context.save()
        try await first.signIn(givenName: "Anna")

        try await second.signIn()

        let sets = try second.context.fetchAll(StoredGoalSet.self)
        #expect(sets.map(\.id) == [stored.id])
        #expect(sets.map(\.goalSet) == [set])
        #expect(sets.allSatisfy { !$0.isWaitingToUpload })
        #expect(second.account.waitingChanges == 0)
        #expect(!second.context.hasChanges)
    }

    /// Both phones made a set for the same week before either had the set
    /// of the other. The server keeps the set that uploaded first.
    @Test func aPhoneWhoseSecondSetTheServerRefusesUsesTheSetOfTheServer() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        try await first.signIn(givenName: "Anna")
        try await second.signIn()
        let firstSet = goalSet(of: bello, [.distance(metres: 5_000), .newLength(metres: 1_000), .newArea])
        let secondSet = goalSet(of: bello, [.refresh(metres: 1_000), .newLength(metres: 1_000), .newArea])
        let kept = StoredGoalSet(firstSet, context: first.context)
        try first.context.save()
        _ = StoredGoalSet(secondSet, context: second.context)
        try second.context.save()

        await first.account.upload()
        await second.account.refresh()

        let sets = try second.context.fetchAll(StoredGoalSet.self)
        #expect(sets.map(\.id) == [kept.id])
        #expect(sets.map(\.goalSet) == [firstSet])
        #expect(server.weeklyGoals.values.map(\.set) == [firstSet])
        #expect(second.account.waitingChanges == 0)
    }

    /// The second phone finishes a goal of the set before it has the swap
    /// of the first phone. The server refuses the stale set, so the second
    /// phone takes the set of the server, and its finish uploads again
    /// later.
    @Test func aPhoneWhoseChangeOfASetTheServerRefusesTakesTheSetOfTheServer() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        let set = goalSet(of: bello, WeeklyGoals.starterGoals)
        let stored = StoredGoalSet(set, context: first.context)
        try first.context.save()
        try await first.signIn(givenName: "Anna")
        try await second.signIn()
        var swapped = set
        swapped.slots[2] = GoalSlot(goal: .newArea, finishedAt: nil)
        swapped.swappedSlot = 2
        stored.update(to: swapped)
        stored.noteChange()
        try first.context.save()
        await first.account.upload()
        let stale = try #require(try second.context.fetchAll(StoredGoalSet.self).first)
        var finished = set
        finished.slots[0].finishedAt = start
        stale.update(to: finished)
        stale.noteChange()
        try second.context.save()

        await second.account.refresh()

        let sets = try second.context.fetchAll(StoredGoalSet.self)
        #expect(sets.map(\.goalSet) == [swapped])
        #expect(sets.allSatisfy { !$0.isWaitingToUpload })
        #expect(second.account.waitingChanges == 0)
    }

    @Test func aRenameOnAPhoneThatHasNotSeenTheMoveKeepsTheMovedHomeBase() async throws {
        let pack = try #require(try first.packs.addDog(named: "Bello").pack)
        try first.packs.setHomeBase(HomeBase(latitude: 47.4, longitude: 8.4), of: pack)
        try await first.signIn(givenName: "Anna")
        try await second.signIn()
        let secondPack = try #require(try second.packs.all().first)

        let moved = HomeBase(latitude: 47.41, longitude: 8.39)
        try first.packs.setHomeBase(moved, of: pack)
        await first.account.upload()
        // The second phone has not downloaded the move yet.
        try second.packs.rename(secondPack, to: "Bellos Rudel")
        await second.account.refresh()

        #expect(server.packs[pack.id]?.homeBase == moved)
        #expect(server.packs[pack.id]?.name == "Bellos Rudel")
        #expect(secondPack.homeBase == moved)
        await first.account.refresh()
        #expect(pack.name == "Bellos Rudel")
        #expect(pack.homeBase == moved)
    }

    @Test func aSecondPhoneGetsTheAreaStepsAndTheEarliestOneOfTwoWins() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        let entry = AreaStep(dog: bello, area: 243, step: .entry, reachedAt: start, context: first.context)
        let half = AreaStep(dog: bello, area: 243, step: .half, reachedAt: start + 60, context: first.context)
        try first.context.save()
        try await first.signIn(givenName: "Anna")

        try await second.signIn()

        let steps = try second.context.fetchAll(AreaStep.self)
        #expect(Set(steps.map(\.id)) == [entry.id, half.id])
        #expect(steps.allSatisfy { $0.dogID == bello.id && $0.area == 243 && !$0.isWaitingToUpload })
        #expect(Set(steps.map(\.reachedAt)) == [start, start + 60])
        #expect(Set(steps.compactMap(\.stampStep)) == [.entry, .half])
        #expect(second.account.waitingChanges == 0)
        #expect(!second.context.hasChanges)

        // The first phone deletes its record of the step because a record
        // from another phone was earlier, and the deletion arrives.
        half.markDeleted()
        try first.context.save()
        await first.account.upload()
        await second.account.refresh()

        let shown = try second.context.fetchAll(AreaStep.self).filter { $0.deletedAt == nil }
        #expect(shown.map(\.id) == [entry.id])
    }

    @Test func aWalkRecordedOnOnePhoneAppearsOnTheOtherAfterARefresh() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        try await first.signIn(givenName: "Anna")
        try await second.signIn()

        let walk = try first.recordWalk(startedAt: start, dogs: [bello])
        await first.account.upload()
        await second.account.refresh()

        #expect(try second.walks().map(\.id) == [walk.id])
        #expect(try second.walks().first?.dogs.map(\.id) == [bello.id])
    }

    @Test func aWalkRecordedOnTheSecondPhoneAppearsOnTheFirst() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        try await first.signIn(givenName: "Anna")
        try await second.signIn()

        let walk = try second.recordWalk(startedAt: start, dogs: [try second.dog(bello.id)])
        await second.account.upload()
        await first.account.refresh()

        #expect(try first.walks().map(\.id) == [walk.id])
        #expect(try first.walks().first?.dogs.map(\.id) == [bello.id])
        #expect(first.account.waitingChanges == 0)
        #expect(second.account.waitingChanges == 0)
    }

    @Test func aWalkDeletedOnOnePhoneDisappearsOnTheOther() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        let walk = try first.recordWalk(startedAt: start, dogs: [bello])
        try await first.signIn(givenName: "Anna")
        try await second.signIn()

        try second.walk(walk.id).markDeleted()
        try second.context.save()
        await second.account.upload()
        await first.account.refresh()

        #expect(try first.walks().isEmpty)
        #expect(walk.deletedAt != nil)
        #expect(!walk.isWaitingToUpload)
    }

    @Test func aChangeToTheDogsOfAWalkArrives() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        let luna = try first.packs.addDog(named: "Luna")
        let walk = try first.recordWalk(startedAt: start, dogs: [bello])
        try await first.signIn(givenName: "Anna")
        try await second.signIn()

        walk.changeDogs(to: [luna])
        try first.context.save()
        await first.account.upload()
        await second.account.refresh()

        #expect(try second.walk(walk.id).dogs.map(\.id) == [luna.id])
    }

    @Test func aRenamedDogWithANewPhotoArrives() async throws {
        let bello = try first.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0x01]))
        try await first.signIn(givenName: "Anna")
        try await second.signIn()

        bello.name = "Bello II"
        bello.photoData = Data([0xFF, 0xD8, 0x02])
        bello.noteChange()
        try first.context.save()
        await first.account.upload()
        await second.account.refresh()

        let secondBello = try second.dog(bello.id)
        #expect(secondBello.name == "Bello II")
        #expect(secondBello.photoData == Data([0xFF, 0xD8, 0x02]))
    }

    @Test func aRemovedPhotoLeavesTheOtherPhone() async throws {
        let bello = try first.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0x01]))
        try await first.signIn(givenName: "Anna")
        try await second.signIn()

        bello.photoData = nil
        bello.noteChange()
        try first.context.save()
        await first.account.upload()
        await second.account.refresh()

        #expect(try second.dog(bello.id).photoData == nil)
    }

    @Test func aDownloadThatRunsTwiceMakesNoDuplicates() async throws {
        let bello = try first.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0x01]))
        try first.recordWalk(startedAt: start, dogs: [bello])
        _ = CompletedArea(dog: bello, area: 243, completedAt: start, context: first.context)
        _ = AreaStep(dog: bello, area: 243, step: .entry, reachedAt: start, context: first.context)
        try first.context.save()
        try await first.signIn(givenName: "Anna")

        try await second.signIn()
        await second.account.refresh()
        await second.account.refresh()

        #expect(try second.context.fetchAll(Pack.self).count == 1)
        #expect(try second.context.fetchAll(Dog.self).count == 1)
        #expect(try second.context.fetchAll(Walk.self).count == 1)
        #expect(try second.context.fetchAll(WalkDog.self).count == 1)
        #expect(try second.context.fetchAll(CompletedArea.self).count == 1)
        #expect(try second.context.fetchAll(AreaStep.self).count == 1)
        #expect(second.account.waitingChanges == 0)
    }

    /// The first phone downloads its own rows back, and they stay as they are.
    @Test func thePhoneThatUploadedTheRowsKeepsThemAsTheyAre() async throws {
        let bello = try first.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0x01]))
        let walk = try first.recordWalk(startedAt: start, dogs: [bello])
        try await first.signIn(givenName: "Anna")

        await first.account.refresh()

        #expect(try first.context.fetchAll(Dog.self).count == 1)
        #expect(try first.context.fetchAll(Walk.self).count == 1)
        #expect(bello.photoData == Data([0xFF, 0xD8, 0x01]))
        #expect(walk.trackData != nil)
        #expect(first.account.waitingChanges == 0)
        #expect(!first.context.hasChanges)
    }

    /// The server keeps dates with milliseconds only. The collections match
    /// a walk again when its start or end changes, so the walk keeps them.
    @Test func thePhoneThatUploadedAWalkKeepsItsExactDates() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        let walk = try first.recordWalk(startedAt: start + 0.000_4, dogs: [bello])
        walk.endedAt = start + 3_600.000_4
        try first.context.save()
        try await first.signIn(givenName: "Anna")

        await first.account.refresh()

        #expect(walk.startedAt == start + 0.000_4)
        #expect(walk.endedAt == start + 3_600.000_4)
        #expect(!first.context.hasChanges)
    }

    @Test func aLaterDownloadAsksForTheChangesSinceTheLastOneWithSomeOverlap() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        let walk = try first.recordWalk(startedAt: start, dogs: [bello])
        try await first.signIn(givenName: "Anna")

        try await second.signIn()
        let firstAsked = server.changedSince["downloadWalks"]
        await second.account.refresh()

        #expect(firstAsked == .some(nil))
        let changedAt = try #require(server.changedAt[walk.id])
        #expect(server.changedSince["downloadWalks"] == changedAt - PackDownload.overlap)
    }

    /// The change uploads later, and so wins on the server.
    @Test func aChangeThatWaitsToUploadIsNotOverwritten() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        try await first.signIn(givenName: "Anna")
        try await second.signIn()
        bello.name = "Bello A"
        bello.noteChange()
        try first.context.save()
        await first.account.upload()

        server.refusedIDs = [bello.id]
        let secondBello = try second.dog(bello.id)
        secondBello.name = "Bello B"
        secondBello.noteChange()
        try second.context.save()
        await second.account.refresh()

        #expect(secondBello.name == "Bello B")
        #expect(secondBello.isWaitingToUpload)
    }

    @Test func aWalkWhoseTrackFailedToDownloadArrivesWithTheNextRefresh() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        let walk = try first.recordWalk(startedAt: start, dogs: [bello])
        try await first.signIn(givenName: "Anna")

        server.failingOnce = ["downloadFile"]
        try await second.signIn()
        let walksAfterFailure = try second.walks()
        await second.account.refresh()

        #expect(walksAfterFailure.isEmpty)
        #expect(try second.walks().map(\.id) == [walk.id])
        #expect(try second.walk(walk.id).trackData == walk.trackData)
        #expect(try second.walk(walk.id).dogs.map(\.id) == [bello.id])
    }

    /// The walks and records of the dog do not wait for its photo.
    /// Each photo has a path of its own, so a new name of the dog does not
    /// download the photo again.
    @Test func aNewNameOfADogDoesNotDownloadItsPhotoAgain() async throws {
        let bello = try first.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0x01]))
        try await first.signIn(givenName: "Anna")
        try await second.signIn()

        bello.name = "Bello II"
        bello.noteChange()
        try first.context.save()
        await first.account.upload()
        let requestsBefore = server.requests.count
        await second.account.refresh()

        #expect(try second.dog(bello.id).name == "Bello II")
        #expect(try second.dog(bello.id).photoData == Data([0xFF, 0xD8, 0x01]))
        #expect(!server.requests.dropFirst(requestsBefore).contains("downloadFile"))
    }

    @Test func aDogWhosePhotoFailedToDownloadArrivesWithItsWalksAndGetsThePhotoLater() async throws {
        let bello = try first.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0x01]))
        let walk = try first.recordWalk(startedAt: start, dogs: [bello])
        try await first.signIn(givenName: "Anna")

        server.failingOnce = ["downloadFile"]
        try await second.signIn()
        let photoAfterFailure = try second.dog(bello.id).photoData
        let changeAfterFailure = try second.dog(bello.id).changedAt
        let dogsOfWalkAfterFailure = try second.walk(walk.id).dogs.map(\.id)
        await second.account.refresh()

        #expect(photoAfterFailure == nil)
        // The dog keeps the change on the server.
        #expect(changeAfterFailure == server.changedAt[bello.id])
        #expect(dogsOfWalkAfterFailure == [bello.id])
        #expect(try second.dog(bello.id).photoData == Data([0xFF, 0xD8, 0x01]))
        #expect(second.account.waitingChanges == 0)
    }

    @Test func atMostFourFilesDownloadAtTheSameTime() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        let walks = try (0..<10).map { try first.recordWalk(startedAt: start + Double($0) * 7_200, dogs: [bello]) }
        try await first.signIn(givenName: "Anna")
        server.requestDelay = .milliseconds(20)
        server.mostFilesAtOnce = 0

        try await second.signIn()

        #expect(server.mostFilesAtOnce == FileTransfers.atATime)
        for walk in walks {
            #expect(try second.walk(walk.id).trackData == walk.trackData)
        }
    }

    @Test func theDownloadAsksForThePackAndTheMembersAlongsideTheTables() async throws {
        try first.packs.addDog(named: "Bello")
        try await first.signIn(givenName: "Anna")
        server.requestDelay = .milliseconds(5)

        try await second.signIn()

        let isTableDownload = { (request: String) in request.hasPrefix("download") && request != "downloadFile" }
        #expect(server.runningAtStart["pack"]?.contains(where: isTableDownload) == true)
        #expect(server.runningAtStart["packMembers"]?.contains(where: isTableDownload) == true)
    }

    /// The download stores the rows after it has downloaded their files, so
    /// a row that changes on the phone during the download keeps its change.
    @Test func aDogThatChangesOnThePhoneDuringTheDownloadKeepsItsChange() async throws {
        let bello = try first.packs.addDog(named: "Bello")
        try await first.signIn(givenName: "Anna")
        try await second.signIn()
        let secondBello = try second.dog(bello.id)
        bello.name = "Bello II"
        bello.noteChange()
        try first.recordWalk(startedAt: start, dogs: [bello])
        await first.account.upload()
        server.beforeRequest = { [context = second.context] name in
            guard name == "downloadFile", secondBello.name == "Bello" else { return }
            secondBello.name = "Bello B"
            secondBello.noteChange()
            try? context.save()
        }

        await second.account.refresh()

        #expect(secondBello.name == "Bello B")
        #expect(server.dogs[bello.id]?.name == "Bello B")
    }

    /// The first phone gives Bello a new photo, and deletes the old one. The
    /// second phone renames Bello before it downloads that change, so its
    /// upload names the old photo. The server keeps the new photo (#130).
    @Test func aNewPhotoStaysWhenAnotherPhoneChangesTheDogBeforeItsDownload() async throws {
        let bello = try first.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0x01]))
        try await first.signIn(givenName: "Anna")
        try await second.signIn()
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
        #expect(server.files.count == 1)
    }

    /// A row can point to a file that Storage does not have, for example from
    /// before #130. The dog and the walk arrive without it, and the next
    /// download does not ask for it again.
    @Test func aRowWhoseFileIsMissingArrivesWithoutItAndTheDownloadMovesOn() async throws {
        let bello = try first.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0x01]))
        let walk = try first.recordWalk(startedAt: start, dogs: [bello])
        try await first.signIn(givenName: "Anna")
        server.files = [:]

        try await second.signIn()
        let requestsBefore = server.requests.count
        await second.account.refresh()

        #expect(try second.dog(bello.id).photoData == nil)
        #expect(try second.walk(walk.id).trackData == nil)
        #expect(second.account.waitingChanges == 0)
        #expect(!server.requests.dropFirst(requestsBefore).contains("downloadFile"))
        #expect(server.changedSince["downloadDogs"] != nil)
    }

    @Test func anUnchangedDogDoesNotDownloadItsPhotoAgain() async throws {
        try first.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0x01]))
        try await first.signIn(givenName: "Anna")
        try await second.signIn()

        let requestsBefore = server.requests.count
        await second.account.refresh()

        #expect(!server.requests.dropFirst(requestsBefore).contains("downloadFile"))
    }

    @Test func aDownloadedPhotoDoesNotUploadAgainWithTheNextChangeOfTheDog() async throws {
        let bello = try first.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0x01]))
        try await first.signIn(givenName: "Anna")
        try await second.signIn()

        let secondBello = try second.dog(bello.id)
        secondBello.name = "Bello II"
        secondBello.noteChange()
        try second.context.save()
        let requestsBefore = server.requests.count
        await second.account.upload()

        #expect(server.dogs[bello.id]?.name == "Bello II")
        #expect(!server.requests.dropFirst(requestsBefore).contains("uploadFile"))
    }

    @Test func aDogAddedDuringTheFirstDownloadMakesNoSecondPack() async throws {
        try first.packs.addDog(named: "Bello")
        try await first.signIn(givenName: "Anna")

        var isLunaAdded = false
        server.beforeRequest = { name in
            if name == "pack", !isLunaAdded {
                isLunaAdded = true
                _ = try? second.packs.addDog(named: "Luna")
            }
        }
        try await second.signIn()

        #expect(try second.context.fetchAll(Pack.self).count == 1)
        #expect(try second.dogs().map(\.name) == ["Luna"])
    }

    /// Bringing the dogs of the phone into the pack of the account is #105.
    @Test func aPhoneWithAnotherPackDownloadsNothing() async throws {
        try first.packs.addDog(named: "Bello")
        try await first.signIn(givenName: "Anna")
        let luna = try second.packs.addDog(named: "Luna")

        try await second.signIn()

        #expect(try second.dogs().map(\.id) == [luna.id])
        #expect(!server.requests.contains("downloadDogs"))
    }

    @Test func theCollectionsOfTheSecondPhoneMatchTheFirstPhone() async throws {
        let fixture = try FixturePackage.url()
        let segments = try FixturePackage.segments()
        let long = try #require(segments.first { $0.id == CollectionEngineTests.longSegmentID })
        let bello = try first.packs.addDog(named: "Bello")
        let start = Date(timeIntervalSinceReferenceDate: 812_000_000)
        try first.recordWalk(startedAt: start, dogs: [bello], track: syntheticTrack(along: long, startingAt: start))
        let firstCollections = Collections(context: first.context, packages: MapPackages(urls: [fixture]), cacheRoot: nil)
        await firstCollections.update()
        try await first.signIn(givenName: "Anna")

        try await second.signIn()
        let secondCollections = Collections(
            context: second.context, packages: MapPackages(urls: [fixture]), cacheRoot: nil)
        await secondCollections.update()

        let collected = firstCollections.collection(of: bello.id).collectedSegments
        #expect(collected.contains(long.id))
        #expect(secondCollections.collection(of: bello.id).collectedSegments == collected)
        #expect(try second.dog(bello.id).completedStreetRecords == bello.completedStreetRecords)
        #expect(try second.dog(bello.id).completedAreaRecords == bello.completedAreaRecords)
    }
}
