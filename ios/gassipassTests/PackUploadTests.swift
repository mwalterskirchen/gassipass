//
//  PackUploadTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

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

        let photoPath = "\(pack.id.uuidString.lowercased())/\(bello.id.uuidString.lowercased()).jpg"
        #expect(server.dogs[bello.id] == ServerDog(
            id: bello.id, packID: pack.id, name: "Bello", photoPath: photoPath, retiredAt: nil,
            retirementReason: "", deletedAt: nil))
        #expect(server.files[ServerFile.dogPhoto(dog: bello.id, pack: pack.id)] == photo)
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

    @Test func aChangedPhotoUploads() async throws {
        let bello = try phone.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8]))
        let pack = try #require(bello.pack)
        try await phone.signIn(givenName: "Anna")

        bello.photoData = Data([0xFF, 0xD9])
        bello.noteChange()
        try phone.context.save()
        await phone.account.upload()

        #expect(server.files[.dogPhoto(dog: bello.id, pack: pack.id)] == Data([0xFF, 0xD9]))
    }

    @Test func aRemovedPhotoLeavesStorage() async throws {
        let bello = try phone.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8]))
        let pack = try #require(bello.pack)
        try await phone.signIn(givenName: "Anna")

        bello.photoData = nil
        bello.noteChange()
        try phone.context.save()
        await phone.account.upload()

        #expect(server.files[.dogPhoto(dog: bello.id, pack: pack.id)] == nil)
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
