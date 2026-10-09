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
    let container: ModelContainer
    let context: ModelContext
    let packs: Packs
    let server = FakeServer()
    let account: Account

    init() throws {
        container = try LocalStore.inMemory()
        context = container.mainContext
        packs = Packs(context: context)
        let defaults = UserDefaults(suiteName: "PackUploadTests-\(UUID().uuidString)")!
        account = Account(server: server, context: context, defaults: defaults)
    }

    func signIn() async throws {
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))
    }

    @Test func aDogUploadsWithItsPhoto() async throws {
        let photo = Data([0xFF, 0xD8, 0xFF])
        let bello = try packs.addDog(named: "Bello", photoData: photo)
        let pack = try #require(bello.pack)

        try await signIn()

        let photoPath = "\(pack.id.uuidString.lowercased())/\(bello.id.uuidString.lowercased()).jpg"
        #expect(server.dogs[bello.id] == ServerDog(
            id: bello.id, packID: pack.id, name: "Bello", photoPath: photoPath, retiredAt: nil,
            retirementReason: "", deletedAt: nil))
        #expect(server.files[ServerFile.dogPhoto(dog: bello.id, pack: pack.id)] == photo)
        #expect(!bello.isWaitingToUpload)
        #expect(!context.hasChanges)
    }

    @Test func anEndedWalkUploadsWithItsTrackAndItsDogs() async throws {
        let bello = try packs.addDog(named: "Bello")
        let pack = try #require(bello.pack)
        let started = Date(timeIntervalSince1970: 1_790_000_000)
        let walk = Walk(startedAt: started, dogs: [bello], context: context)
        walk.store(Track(points: [
            TrackPoint(latitude: 47.4, longitude: 8.4, timestamp: started, horizontalAccuracy: 5),
            TrackPoint(latitude: 47.401, longitude: 8.4, timestamp: started + 60, horizontalAccuracy: 5),
        ]))
        walk.endedAt = started + 3_600
        walk.deviceID = "phone"
        walk.memberName = "Nina"
        try context.save()

        try await signIn()

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
        let bello = try packs.addDog(named: "Bello")
        let walk = Walk(startedAt: .now, dogs: [bello], context: context)
        try context.save()
        try await signIn()

        #expect(server.walks.isEmpty)
        #expect(server.walkDogs.isEmpty)

        walk.store(Track())
        walk.endedAt = .now
        walk.noteChange()
        try context.save()
        await account.upload()

        #expect(server.walks[walk.id] != nil)
        #expect(server.walkDogs.count == 1)
    }

    @Test func theCompletedRecordsUpload() async throws {
        let bello = try packs.addDog(named: "Bello")
        let pack = try #require(bello.pack)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let area = CompletedArea(dog: bello, area: 243, completedAt: date, context: context)
        let street = CompletedStreet(
            dog: bello, street: Street.ID(area: 243, name: "Zürcherstrasse"), completedAt: date, context: context)
        try context.save()

        try await signIn()

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
    func endedWalk(dogs: [Dog]) throws -> Walk {
        let walk = Walk(startedAt: .now - 3_600, dogs: dogs, context: context)
        walk.store(Track())
        walk.endedAt = .now
        try context.save()
        return walk
    }

    @Test func aRenamedRetiredDogAChangeToTheDogsOfAWalkAndADeletedWalkUpload() async throws {
        let bello = try packs.addDog(named: "Bello")
        let luna = try packs.addDog(named: "Luna")
        let walk = try endedWalk(dogs: [bello])
        let deleted = try endedWalk(dogs: [bello])
        try await signIn()

        bello.name = "Bello II"
        bello.retire(on: Date(timeIntervalSince1970: 1_790_000_000), reason: "Old age")
        bello.noteChange()
        walk.changeDogs(to: [luna])
        deleted.markDeleted()
        try context.save()
        await account.upload()

        #expect(server.dogs[bello.id]?.name == "Bello II")
        #expect(server.dogs[bello.id]?.retiredAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(server.dogs[bello.id]?.retirementReason == "Old age")
        let dogsOfWalk = server.walkDogs.values.filter { $0.walkID == walk.id && $0.deletedAt == nil }
        #expect(dogsOfWalk.map(\.dogID) == [luna.id])
        #expect(server.walks[deleted.id]?.deletedAt == deleted.deletedAt)
        #expect(server.walks[deleted.id]?.deletedAt != nil)
    }

    @Test func aWalkWhoseTrackFailedToUploadUploadsWithTheNextUpload() async throws {
        let bello = try packs.addDog(named: "Bello")
        let walk = try endedWalk(dogs: [bello])
        server.failingOnce = ["uploadFile"]

        try await signIn()
        let walksAfterFailure = server.walks
        let walkDogsAfterFailure = server.walkDogs
        await account.upload()

        #expect(server.dogs[bello.id] != nil)
        #expect(walksAfterFailure.isEmpty)
        #expect(walkDogsAfterFailure.isEmpty)
        #expect(server.walks[walk.id] != nil)
        #expect(server.walkDogs.count == 1)
        #expect(!walk.isWaitingToUpload)
    }

    /// The dogs of the phone first have to move into the pack of the account
    /// (ADR 0005).
    @Test func nothingUploadsWhenTheAccountIsInAnotherPack() async throws {
        let bello = try packs.addDog(named: "Bello")
        try endedWalk(dogs: [bello])
        server.member.packID = UUID()

        try await signIn()

        #expect(server.dogs.isEmpty)
        #expect(server.walks.isEmpty)
        #expect(bello.isWaitingToUpload)
    }

    @Test func theAccountCountsTheChangesThatWaitToUpload() async throws {
        let bello = try packs.addDog(named: "Bello")
        try endedWalk(dogs: [bello])
        _ = Walk(startedAt: .now, dogs: [bello], context: context)
        _ = CompletedArea(dog: bello, area: 243, completedAt: .now, context: context)
        try context.save()
        server.failingOnce = ["uploadDogs"]

        try await signIn()
        let waitingAfterFailure = account.waitingChanges
        await account.upload()

        // The dog, the dog of the ended walk and the completed record wait.
        // The walk that is still being recorded does not count.
        #expect(waitingAfterFailure == 3)
        #expect(account.waitingChanges == 0)
    }

    @Test func aSavedChangeUploads() async throws {
        let connections = AsyncStream<Void>.makeStream()
        let watching = Task { await account.uploadChanges(whenConnected: connections.stream) }
        defer { watching.cancel() }
        try await signIn()
        try await Task.sleep(for: .milliseconds(50))

        let bello = try packs.addDog(named: "Bello")

        try await eventually { server.dogs[bello.id] != nil && account.waitingChanges == 0 }
    }

    @Test func aWalkRecordedOfflineUploadsWhenTheNetworkComesBack() async throws {
        let connections = AsyncStream<Void>.makeStream()
        let watching = Task { await account.uploadChanges(whenConnected: connections.stream) }
        defer { watching.cancel() }
        try await signIn()
        try await Task.sleep(for: .milliseconds(50))
        let bello = try packs.addDog(named: "Bello")
        try await eventually { server.dogs[bello.id] != nil }

        server.isOffline = true
        let walk = try endedWalk(dogs: [bello])
        try await eventually { account.waitingChanges == 2 }
        server.isOffline = false
        connections.continuation.yield()

        try await eventually { server.walks[walk.id] != nil && account.waitingChanges == 0 }
    }
}
