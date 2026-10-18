//
//  PackUploadTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The upload of the dogs, the walks and the completed records of the pack,
/// through the account, with a server in memory.
@MainActor
struct PackUploadTests {
    let server = FakeServer()
    let phone: Phone<FakeServer>

    init() throws {
        phone = try Phone(server: server)
    }

    @Test func aDogUploadsWithItsPhoto() async throws {
        let photo = Data([0xFF, 0xD8, 0xFF])
        let bello = try phone.packs.addDog(named: "Bello", photoData: photo)
        let pack = try #require(bello.pack)

        try await phone.signIn(givenName: "Anna")

        let file = ServerFile.dogPhoto(dog: bello.id, pack: pack.id, data: photo)
        #expect(file.path.hasPrefix("\(pack.id.uuidString.lowercased())/\(bello.id.uuidString.lowercased())-"))
        #expect(server.dogs[bello.id] == ServerDog(
            id: bello.id, packID: pack.id, name: "Bello", photoPath: file.path, retiredAt: nil,
            retirementReason: "", deletedAt: nil))
        #expect(server.files[file] == photo)
        #expect(!bello.isWaitingToUpload)
        #expect(!phone.context.hasChanges)
    }

    @Test func anEndedWalkUploadsWithItsTrackAndItsDogs() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        let pack = try #require(bello.pack)
        let started = Date(timeIntervalSince1970: 1_790_000_000)
        let walk = Walk(startedAt: started, dogs: [bello], context: phone.context)
        walk.store(Track(points: [
            TrackPoint(latitude: 47.4, longitude: 8.4, timestamp: started, horizontalAccuracy: 5),
            TrackPoint(latitude: 47.401, longitude: 8.4, timestamp: started + 60, horizontalAccuracy: 5),
        ]))
        walk.endedAt = started + 3_600
        walk.deviceID = "phone"
        walk.memberName = "Nina"
        try phone.context.save()

        try await phone.signIn(givenName: "Anna")

        let track = ServerFile.track(walk: walk.id, pack: pack.id)
        #expect(server.walks[walk.id] == ServerWalk(
            id: walk.id, packID: pack.id, startedAt: started, endedAt: started + 3_600, trackPath: track.path,
            distanceMetres: walk.distanceMetres, distanceVersion: WalkDistance.version, continuedAt: nil,
            deviceID: "phone", memberName: "Nina", deletedAt: nil))
        #expect(server.files[track] == walk.trackData)
        let walkDog = try #require(walk.walkDogs?.first)
        #expect(server.walkDogs[walkDog.id] == ServerWalkDog(
            id: walkDog.id, packID: pack.id, walkID: walk.id, dogID: bello.id, deletedAt: nil))
        #expect(!walk.isWaitingToUpload)
        #expect(!walkDog.isWaitingToUpload)
    }

    @Test func aWalkThatIsStillBeingRecordedWaitsUntilItEnds() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        let walk = Walk(startedAt: .now, dogs: [bello], context: phone.context)
        try phone.context.save()
        try await phone.signIn(givenName: "Anna")

        #expect(server.walks.isEmpty)
        #expect(server.walkDogs.isEmpty)

        walk.store(Track())
        walk.endedAt = .now
        walk.noteChange()
        try phone.context.save()
        await phone.account.upload()

        #expect(server.walks[walk.id] != nil)
        #expect(server.walkDogs.count == 1)
    }

    @Test func theCompletedRecordsUpload() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        let pack = try #require(bello.pack)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let area = CompletedArea(dog: bello, area: 243, completedAt: date, context: phone.context)
        let street = CompletedStreet(
            dog: bello, street: Street.ID(area: 243, name: "Zürcherstrasse"), completedAt: date, context: phone.context)
        try phone.context.save()

        try await phone.signIn(givenName: "Anna")

        #expect(server.completedAreas[area.id] == ServerCompletedArea(
            id: area.id, packID: pack.id, dogID: bello.id, area: 243, completedAt: date, deletedAt: nil))
        #expect(server.completedStreets[street.id] == ServerCompletedStreet(
            id: street.id, packID: pack.id, dogID: bello.id, area: 243, street: "Zürcherstrasse",
            completedAt: date, deletedAt: nil))
        #expect(!area.isWaitingToUpload)
        #expect(!street.isWaitingToUpload)
    }

    @Test func theAreaStepsUploadAfterTheirDog() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        let pack = try #require(bello.pack)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let step = AreaStep(dog: bello, area: 243, step: .half, reachedAt: date, context: phone.context)
        try phone.context.save()
        server.failingOnce = ["uploadDogs"]

        try await phone.signIn(givenName: "Anna")
        // The dog waits, so its step waits for it.
        #expect(server.areaSteps.isEmpty)
        #expect(phone.account.waitingChanges == 2)
        await phone.account.upload()

        #expect(server.areaSteps[step.id] == ServerAreaStep(
            id: step.id, packID: pack.id, dogID: bello.id, area: 243, step: 50, reachedAt: date, deletedAt: nil))
        #expect(!step.isWaitingToUpload)
        #expect(phone.account.waitingChanges == 0)
    }

    @Test func theRingStampsUploadAfterTheirDog() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        let pack = try #require(bello.pack)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let ring = Ring(number: 2, centre: HomeBase(latitude: 47.4, longitude: 8.4))
        let stamp = CompletedRing(dogID: bello.id, ring: ring, completedAt: date, context: phone.context)
        try phone.context.save()
        server.failingOnce = ["uploadDogs"]

        try await phone.signIn(givenName: "Anna")
        // The dog waits, so its ring stamp waits for it.
        #expect(server.completedRings.isEmpty)
        await phone.account.upload()

        #expect(server.completedRings[stamp.id] == ServerCompletedRing(
            id: stamp.id, packID: pack.id, dogID: bello.id, ring: 2, radiusMetres: 350, centreLatitude: 47.4,
            centreLongitude: 8.4, completedAt: date, deletedAt: nil))
        #expect(!stamp.isWaitingToUpload)
        #expect(phone.account.waitingChanges == 0)
    }

    @Test func theWeeklyGoalsUploadAfterTheirDog() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        let pack = try #require(bello.pack)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let set = WeeklyGoalSet(
            dog: bello.id, weekStart: WeekCalendar.week(containing: date).start,
            slots: [
                GoalSlot(goal: .distance(metres: 5_000), finishedAt: date),
                GoalSlot(goal: .street(Street.ID(area: 243, name: "Kirchweg")), finishedAt: nil),
                GoalSlot(goal: .areaStep(AreaStepID(area: 243, step: .half)), finishedAt: nil),
            ],
            swappedSlot: 1)
        let stored = StoredGoalSet(set, context: phone.context)
        try phone.context.save()
        server.failingOnce = ["uploadDogs"]

        try await phone.signIn(givenName: "Anna")
        // The dog waits, so its weekly goals wait for it.
        #expect(server.weeklyGoals.isEmpty)
        await phone.account.upload()

        #expect(server.weeklyGoals[stored.id]?.packID == pack.id)
        #expect(server.weeklyGoals[stored.id]?.set == set)
        #expect(!stored.isWaitingToUpload)
        #expect(phone.account.waitingChanges == 0)
    }

    @Test func theHomeBaseUploadsWithANewPackAndAgainWhenItMoves() async throws {
        let pack = try #require(try phone.packs.addDog(named: "Bello").pack)
        let home = HomeBase(latitude: 47.4, longitude: 8.4)
        try phone.packs.setHomeBase(home, of: pack)

        try await phone.signIn(givenName: "Anna")

        #expect(server.packs[pack.id]?.homeBase == home)
        #expect(server.packs[pack.id]?.homeSetAt == pack.homeSetAt)
        #expect(!pack.isWaitingToUpload)

        let moved = HomeBase(latitude: 47.41, longitude: 8.39)
        try phone.packs.setHomeBase(moved, of: pack)
        await phone.account.upload()

        #expect(server.packs[pack.id]?.homeBase == moved)
        #expect(server.packs[pack.id]?.name == "")
        #expect(!pack.isWaitingToUpload)
    }

    @Test func aStepOfADogThatThePhoneDoesNotHaveStopsWaiting() async throws {
        _ = try phone.packs.addDog(named: "Bello")
        phone.context.insert(AreaStep(dogID: UUID(), area: 243, step: 0, reachedAt: .now))
        try phone.context.save()

        try await phone.signIn(givenName: "Anna")

        #expect(server.areaSteps.isEmpty)
        #expect(phone.account.waitingChanges == 0)
        #expect(!phone.context.hasChanges)
    }

    /// Stores an ended walk with the dogs, and saves.
    @discardableResult
    @Test func aRenamedRetiredDogAChangeToTheDogsOfAWalkAndADeletedWalkUpload() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        let luna = try phone.packs.addDog(named: "Luna")
        let walk = try phone.recordWalk(dogs: [bello], track: Track())
        let deleted = try phone.recordWalk(dogs: [bello], track: Track())
        try await phone.signIn(givenName: "Anna")

        bello.name = "Bello II"
        bello.retire(on: Date(timeIntervalSince1970: 1_790_000_000), reason: "Old age")
        bello.noteChange()
        walk.changeDogs(to: [luna])
        deleted.markDeleted()
        try phone.context.save()
        await phone.account.upload()

        #expect(server.dogs[bello.id]?.name == "Bello II")
        #expect(server.dogs[bello.id]?.retiredAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(server.dogs[bello.id]?.retirementReason == "Old age")
        let dogsOfWalk = server.walkDogs.values.filter { $0.walkID == walk.id && $0.deletedAt == nil }
        #expect(dogsOfWalk.map(\.dogID) == [luna.id])
        #expect(server.walks[deleted.id]?.deletedAt == deleted.deletedAt)
        #expect(server.walks[deleted.id]?.deletedAt != nil)
    }

    @Test func aWalkWhoseTrackFailedToUploadUploadsWithTheNextUpload() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        let walk = try phone.recordWalk(dogs: [bello], track: Track())
        server.failingOnce = ["uploadFile"]

        try await phone.signIn(givenName: "Anna")
        let walksAfterFailure = server.walks
        let walkDogsAfterFailure = server.walkDogs
        await phone.account.upload()

        #expect(server.dogs[bello.id] != nil)
        #expect(walksAfterFailure.isEmpty)
        #expect(walkDogsAfterFailure.isEmpty)
        #expect(server.walks[walk.id] != nil)
        #expect(server.walkDogs.count == 1)
        #expect(!walk.isWaitingToUpload)
    }

    @Test func aRowThatTheServerRefusesDoesNotStopTheOtherRows() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        let luna = try phone.packs.addDog(named: "Luna")
        server.refusedIDs = [bello.id]

        try await phone.signIn(givenName: "Anna")

        #expect(server.dogs[luna.id] != nil)
        #expect(!luna.isWaitingToUpload)
        #expect(bello.isWaitingToUpload)
        #expect(phone.account.waitingChanges == 1)
    }

    /// The dogs of the phone first have to move into the pack of the account
    /// (ADR 0005).
    @Test func nothingUploadsWhenTheAccountIsInAnotherPack() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        try phone.recordWalk(dogs: [bello], track: Track())
        server.member.packID = UUID()

        try await phone.signIn(givenName: "Anna")

        #expect(server.dogs.isEmpty)
        #expect(server.walks.isEmpty)
        #expect(bello.isWaitingToUpload)
    }

    @Test func theAccountCountsTheChangesThatWaitToUpload() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        try phone.recordWalk(dogs: [bello], track: Track())
        _ = Walk(startedAt: .now, dogs: [bello], context: phone.context)
        _ = CompletedArea(dog: bello, area: 243, completedAt: .now, context: phone.context)
        try phone.context.save()
        server.failingOnce = ["uploadDogs"]

        try await phone.signIn(givenName: "Anna")
        let waitingAfterFailure = phone.account.waitingChanges
        await phone.account.upload()

        // The dog, the dog of the ended walk and the completed record wait.
        // The walk that is still being recorded does not count.
        #expect(waitingAfterFailure == 3)
        #expect(phone.account.waitingChanges == 0)
    }

    @Test func aSavedChangeUploads() async throws {
        let connections = AsyncStream<Void>.makeStream()
        let watching = Task { await phone.account.uploadChanges(whenConnected: connections.stream) }
        defer { watching.cancel() }
        try await phone.signIn(givenName: "Anna")
        try await Task.sleep(for: .milliseconds(50))

        let bello = try phone.packs.addDog(named: "Bello")

        try await eventually { server.dogs[bello.id] != nil && phone.account.waitingChanges == 0 }
    }

    @Test func aWalkRecordedOfflineUploadsWhenTheNetworkComesBack() async throws {
        let connections = AsyncStream<Void>.makeStream()
        let watching = Task { await phone.account.uploadChanges(whenConnected: connections.stream) }
        defer { watching.cancel() }
        try await phone.signIn(givenName: "Anna")
        try await Task.sleep(for: .milliseconds(50))
        let bello = try phone.packs.addDog(named: "Bello")
        try await eventually { server.dogs[bello.id] != nil }

        server.isOffline = true
        let walk = try phone.recordWalk(dogs: [bello], track: Track())
        try await eventually { phone.account.waitingChanges == 2 }
        server.isOffline = false
        connections.continuation.yield()

        try await eventually { server.walks[walk.id] != nil && phone.account.waitingChanges == 0 }
    }

    @Test func anUnchangedPhotoAndTrackDoNotUploadAgain() async throws {
        let bello = try phone.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8]))
        let walk = try phone.recordWalk(dogs: [bello], track: Track())
        try await phone.signIn(givenName: "Anna")
        let fileUploads = server.requests.count { $0 == "uploadFile" }

        bello.name = "Bello II"
        bello.noteChange()
        // Like a new distance after a change of its rules.
        walk.distanceVersion += 1
        walk.noteChange()
        try phone.context.save()
        await phone.account.upload()

        #expect(fileUploads == 2)
        #expect(server.requests.count { $0 == "uploadFile" } == 2)
        #expect(server.dogs[bello.id]?.photoPath != nil)
        #expect(server.walks[walk.id]?.trackPath != nil)
    }

    @Test func aNewPhotoUploadsToANewPathAndTheOldPhotoLeavesTheServer() async throws {
        let bello = try phone.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8]))
        let pack = try #require(bello.pack)
        try await phone.signIn(givenName: "Anna")

        bello.photoData = Data([0xFF, 0xD9])
        bello.noteChange()
        try phone.context.save()
        await phone.account.upload()

        let newPhoto = ServerFile.dogPhoto(dog: bello.id, pack: pack.id, data: Data([0xFF, 0xD9]))
        #expect(server.files == [newPhoto: Data([0xFF, 0xD9])])
        #expect(server.dogs[bello.id]?.photoPath == newPhoto.path)
    }

    /// Before #127, the phone noted each file by its path, and each dog had
    /// one path for its photo. After the update, a file that has not
    /// changed does not upload again, and a new photo takes the old one off
    /// the server.
    @Test func theFilesFromBeforeTheUpdateDoNotUploadAgainAndLeaveNothingBehind() async throws {
        let photo = Data([0xFF, 0xD8])
        let bello = try phone.packs.addDog(named: "Bello", photoData: photo)
        let pack = try #require(bello.pack)
        let walk = try phone.recordWalk(dogs: [bello])
        let track = try #require(walk.trackData)
        try await phone.signIn(givenName: "Anna")
        let oldPhoto = ServerFile(
            bucket: .dogPhotos, path: "\(ServerFile.folder(of: pack.id))/\(bello.id.uuidString.lowercased()).jpg")
        let trackFile = ServerFile.track(walk: walk.id, pack: pack.id)
        server.files = [oldPhoto: photo, trackFile: track]
        server.dogs[bello.id]?.photoPath = oldPhoto.path
        let defaults = emptyDefaults()
        defaults.set([
            "dog-photos/\(oldPhoto.path)": SHA256.hex(of: photo),
            "tracks/\(trackFile.path)": SHA256.hex(of: track),
        ], forKey: "uploadedFiles")
        let updated = Account(server: server, context: phone.context, defaults: defaults)

        bello.name = "Bello II"
        bello.noteChange()
        walk.noteChange()
        try phone.context.save()
        let requestsBefore = server.requests.count
        await updated.upload()
        let requestsOfTheChange = server.requests.dropFirst(requestsBefore)
        let photoPathAfterTheChange = server.dogs[bello.id]?.photoPath
        bello.photoData = Data([0xFF, 0xD9])
        bello.noteChange()
        try phone.context.save()
        await updated.upload()

        #expect(!requestsOfTheChange.contains("uploadFile"))
        #expect(!requestsOfTheChange.contains("deleteFile"))
        #expect(photoPathAfterTheChange == oldPhoto.path)
        let newPhoto = ServerFile.dogPhoto(dog: bello.id, pack: pack.id, data: Data([0xFF, 0xD9]))
        #expect(server.files == [newPhoto: Data([0xFF, 0xD9]), trackFile: track])
        #expect(server.dogs[bello.id]?.photoPath == newPhoto.path)
        #expect(updated.waitingChanges == 0)
    }

    @Test func atMostFourFilesUploadAtTheSameTime() async throws {
        let dogs = try (0..<10).map {
            try phone.packs.addDog(named: "Dog \($0)", photoData: Data([0xFF, 0xD8, UInt8($0)]))
        }
        server.requestDelay = .milliseconds(20)

        try await phone.signIn(givenName: "Anna")

        #expect(server.mostFilesAtOnce == FileTransfers.atATime)
        #expect(server.files.count == 10)
        #expect(dogs.allSatisfy { server.dogs[$0.id]?.photoPath != nil })
    }

    /// Without a network, every request fails after its timeout. So the
    /// upload starts no other file and no other request after the first
    /// failed file.
    @Test func anUploadWithoutANetworkStopsAfterTheFirstFailedFile() async throws {
        try await phone.signIn(givenName: "Anna")
        for index in 0..<10 {
            try phone.packs.addDog(named: "Dog \(index)", photoData: Data([0xFF, 0xD8, UInt8(index)]))
        }
        let requestsBefore = server.requests.count
        server.beforeRequest = { [weak server] name in
            if name == "uploadFile" {
                server?.isOffline = true
            }
        }

        await phone.account.upload()

        let fromFirstFile = server.requests.dropFirst(requestsBefore).drop { $0 != "uploadFile" }
        #expect(!fromFirstFile.isEmpty)
        #expect(fromFirstFile.count <= FileTransfers.atATime)
        #expect(fromFirstFile.allSatisfy { $0 == "uploadFile" })
        #expect(phone.account.waitingChanges == 10)
    }

    @Test func aRemovedPhotoLeavesStorage() async throws {
        let bello = try phone.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8]))
        let pack = try #require(bello.pack)
        try await phone.signIn(givenName: "Anna")

        bello.photoData = nil
        bello.noteChange()
        try phone.context.save()
        await phone.account.upload()

        #expect(server.files[.dogPhoto(dog: bello.id, pack: pack.id, data: Data([0xFF, 0xD8]))] == nil)
        #expect(server.dogs[bello.id]?.photoPath == nil)
    }

    /// A walk that is deleted before it uploads needs no GPS track on the
    /// server.
    @Test func aWalkDeletedBeforeItsUploadUploadsWithoutItsTrack() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        let walk = try phone.recordWalk(dogs: [bello], track: Track())
        walk.markDeleted()
        try phone.context.save()

        try await phone.signIn(givenName: "Anna")

        #expect(server.walks[walk.id]?.deletedAt != nil)
        #expect(server.walks[walk.id]?.trackPath == nil)
        #expect(!server.requests.contains("uploadFile"))
    }

    @Test func afterAFailedUploadOnlyANewChangeUploadsAgain() async throws {
        let connections = AsyncStream<Void>.makeStream()
        let watching = Task { await phone.account.uploadChanges(whenConnected: connections.stream) }
        defer { watching.cancel() }
        try await phone.signIn(givenName: "Anna")
        try await Task.sleep(for: .milliseconds(50))
        let bello = try phone.packs.addDog(named: "Bello")
        try await eventually { server.dogs[bello.id] != nil }

        server.isOffline = true
        try phone.recordWalk(dogs: [bello], track: Track())
        try await eventually { phone.account.waitingChanges == 2 }
        // The waiting changes count at the save, before the upload fails. An
        // upload returns when the running upload has ended.
        await phone.account.upload()
        let requestsAfterFailure = server.requests.count
        // A save without a new change, like the regular save of a walk that
        // is being recorded.
        phone.context.insert(PinnedArea(area: 243))
        try phone.context.save()
        try await Task.sleep(for: .milliseconds(100))
        let requestsAfterSave = server.requests.count
        try phone.recordWalk(dogs: [bello], track: Track())

        #expect(requestsAfterSave == requestsAfterFailure)
        try await eventually { server.requests.count > requestsAfterSave && phone.account.waitingChanges == 4 }
    }

    /// For example after the server lost the pack.
    @Test func everythingUploadsAgainWhenTheAccountHasNoPack() async throws {
        let bello = try phone.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8]))
        let pack = try #require(bello.pack)
        let walk = try phone.recordWalk(dogs: [bello], track: Track())
        try await phone.signIn(givenName: "Anna")

        let fresh = FakeServer()
        fresh.isSignedIn = true
        let freshAccount = Account(server: fresh, context: phone.context, defaults: phone.defaults)
        await freshAccount.upload()

        #expect(fresh.member.packID == pack.id)
        #expect(fresh.dogs[bello.id] != nil)
        #expect(fresh.walks[walk.id] != nil)
        #expect(fresh.walkDogs.count == 1)
        #expect(fresh.files.count == 2)
        #expect(freshAccount.waitingChanges == 0)
    }

    @Test func aDeletedWalkTakesItsTrackOffTheServer() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        let pack = try #require(bello.pack)
        let walk = try phone.recordWalk(dogs: [bello], track: Track())
        try await phone.signIn(givenName: "Anna")

        walk.markDeleted()
        try phone.context.save()
        await phone.account.upload()

        #expect(server.files[.track(walk: walk.id, pack: pack.id)] == nil)
        #expect(server.walks[walk.id]?.trackPath == nil)
        #expect(server.walks[walk.id]?.deletedAt != nil)
    }

    /// Without a network, or with an expired session, each row would fail
    /// on its own too.
    @Test func aBatchThatFailsWithoutARefusalDoesNotUploadRowByRow() async throws {
        try phone.packs.addDog(named: "Bello")
        try phone.packs.addDog(named: "Luna")
        server.failingOnce = ["uploadDogs"]

        try await phone.signIn(givenName: "Anna")

        #expect(server.requests.count { $0 == "uploadDogs" } == 1)
        #expect(server.dogs.isEmpty)
        #expect(phone.account.waitingChanges == 2)
    }

    @Test func anUploadRunsOnceAlthoughItSavesItself() async throws {
        let connections = AsyncStream<Void>.makeStream()
        let watching = Task { await phone.account.uploadChanges(whenConnected: connections.stream) }
        defer { watching.cancel() }
        let bello = try phone.packs.addDog(named: "Bello")
        try phone.recordWalk(dogs: [bello], track: Track())
        try await Task.sleep(for: .milliseconds(50))

        try await phone.signIn(givenName: "Anna")
        try await Task.sleep(for: .milliseconds(100))

        #expect(server.requests.count { $0 == "member" } == 1)
        #expect(phone.account.waitingChanges == 0)
    }

    @Test func aChangeDuringTheUploadUploadsWhenTheUploadEnds() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        server.beforeRequest = { [context = phone.context] name in
            guard name == "uploadDogs", bello.name == "Bello" else { return }
            bello.name = "Bello II"
            bello.noteChange()
            try? context.save()
        }

        try await phone.signIn(givenName: "Anna")

        #expect(server.dogs[bello.id]?.name == "Bello II")
        #expect(phone.account.waitingChanges == 0)
    }

    /// The pack of the phone waits until its dogs move into the pack of the
    /// account (ADR 0005), and the phone does not ask the server at each save.
    @Test func aPhoneWhosePackWaitsDoesNotUploadAtEachSave() async throws {
        let connections = AsyncStream<Void>.makeStream()
        let watching = Task { await phone.account.uploadChanges(whenConnected: connections.stream) }
        defer { watching.cancel() }
        try phone.packs.addDog(named: "Bello")
        server.member.packID = UUID()
        try await Task.sleep(for: .milliseconds(50))
        try await phone.signIn(givenName: "Anna")
        try await Task.sleep(for: .milliseconds(50))
        let requestsAfterSignIn = server.requests.count

        phone.context.insert(PinnedArea(area: 243))
        try phone.context.save()
        try await Task.sleep(for: .milliseconds(100))

        #expect(server.requests.count == requestsAfterSignIn)
    }

    @Test func aRecordWithoutADogStopsWaitingAlsoWhenAnotherRecordIsRefused() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        phone.context.insert(CompletedArea(dog: nil, area: 243, completedAt: .now))
        let refused = CompletedArea(dog: bello, area: 247, completedAt: .now, context: phone.context)
        try phone.context.save()
        server.refusedIDs = [refused.id]

        try await phone.signIn(givenName: "Anna")

        #expect(phone.account.waitingChanges == 1)
        #expect(!phone.context.hasChanges)
    }
}
