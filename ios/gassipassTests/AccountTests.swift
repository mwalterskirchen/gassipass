//
//  AccountTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The account of the person on the phone, with a server in memory.
@MainActor
struct AccountTests {
    let container: ModelContainer
    let context: ModelContext
    let packs: Packs
    let server = FakeServer()
    let defaults: UserDefaults
    let account: Account

    init() throws {
        container = try LocalStore.inMemory()
        context = container.mainContext
        packs = Packs(context: context)
        defaults = UserDefaults(suiteName: "AccountTests-\(UUID().uuidString)")!
        account = Account(server: server, context: context, defaults: defaults)
    }

    @Test func aPersonWithoutAnAccountMakesNoRequest() async throws {
        try packs.addDog(named: "Bello")

        await account.upload()

        #expect(!account.isSignedIn)
        #expect(server.requests.isEmpty)
    }

    @Test func theSignInFillsInTheMemberNameAndUploadsThePackWithThePersonAsPackOwner() async throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        try packs.rename(pack, to: "Bellos Rudel")

        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))

        #expect(account.isSignedIn)
        #expect(account.memberName == "Anna")
        #expect(server.member == ServerMember(name: "Anna", packID: pack.id))
        #expect(server.packs == [pack.id: FakeServer.StoredPack(name: "Bellos Rudel", createdAt: pack.createdAt)])
        #expect(!pack.isWaitingToUpload)
        #expect(!context.hasChanges)
    }

    /// Apple gives the name only at the first sign-in of the person.
    @Test func aLaterSignInTakesTheMemberNameFromTheServer() async throws {
        server.member.name = "Anna"

        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: nil))

        #expect(account.memberName == "Anna")
        #expect(!server.requests.contains("renameMember"))
    }

    @Test func aPersonInNoPackUploadsThePackThatStartsWithTheirFirstDog() async throws {
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))
        #expect(!server.requests.contains("createPack"))

        let pack = try #require(try packs.addDog(named: "Bello").pack)
        await account.upload()

        #expect(server.member.packID == pack.id)
        #expect(server.packs[pack.id]?.name == "")
    }

    /// The dogs of the phone move into the pack of the account only after a
    /// confirmation (ADR 0005). Until then, the pack of the phone waits.
    @Test func aSignInWithAPackOnThePhoneAsksBeforeItsDogsMoveIntoThePackOfTheAccount() async throws {
        let luna = try packs.addDog(named: "Luna")
        let ownPack = try #require(luna.pack)
        let annasPack = UUID()
        server.packs[annasPack] = FakeServer.StoredPack(name: "Annas Rudel", createdAt: .now)
        server.member.packID = annasPack

        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Ben"))

        #expect(account.packOfAccount?.name == "Annas Rudel")
        #expect(server.dogs.isEmpty)
        #expect(server.packs.keys.sorted() == [annasPack])
        #expect(try packs.all() == [ownPack])
        #expect(ownPack.isWaitingToUpload)

        await account.moveDogsIntoPackOfAccount()

        #expect(account.packOfAccount == nil)
        #expect(server.dogs[luna.id]?.packID == annasPack)
        #expect(server.packs[annasPack]?.name == "Annas Rudel")
        #expect(try context.fetchAll(Pack.self).map(\.id) == [annasPack])
        #expect(luna.pack?.id == annasPack)
        #expect(account.waitingChanges == 0)
    }

    /// The pack of the phone has uploaded, but the account is now in another
    /// pack, and the server did not move the dogs. After the confirmation,
    /// the dogs upload again into the pack of the account, with their photos.
    @Test func aConfirmedMoveOfAnUploadedPackThatTheServerDidNotMoveUploadsItsDogsAgain() async throws {
        let luna = try packs.addDog(named: "Luna", photoData: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Ben"))
        let annasPack = UUID()
        server.packs[annasPack] = FakeServer.StoredPack(name: "Annas Rudel", createdAt: .now)
        server.member.packID = annasPack
        await account.refresh()

        await account.moveDogsIntoPackOfAccount()

        #expect(server.dogs[luna.id]?.packID == annasPack)
        #expect(server.files[.dogPhoto(dog: luna.id, pack: annasPack)] == luna.photoData)
        #expect(account.waitingChanges == 0)
    }

    /// A restart of the app does not lose the confirmation.
    @Test func aConfirmedMoveHappensAfterAFailure() async throws {
        let luna = try packs.addDog(named: "Luna")
        let annasPack = UUID()
        server.packs[annasPack] = FakeServer.StoredPack(name: "Annas Rudel", createdAt: .now)
        server.member.packID = annasPack
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Ben"))
        server.isOffline = true

        await account.moveDogsIntoPackOfAccount()
        server.isOffline = false
        let restarted = Account(server: server, context: context, defaults: defaults)
        await restarted.refresh()

        #expect(server.dogs[luna.id]?.packID == annasPack)
        #expect(luna.pack?.id == annasPack)
    }

    @Test func theMemberChangesTheirNameAndTheChangeUploads() async throws {
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))

        await account.renameMember(to: " Anni ")

        #expect(account.memberName == "Anni")
        #expect(server.member.name == "Anni")
    }

    @Test func aNameThatFailedToUploadUploadsWithTheNextUpload() async throws {
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))
        server.failingOnce = ["renameMember"]

        await account.renameMember(to: "Anni")
        let nameAfterFailure = server.member.name
        await account.upload()

        #expect(nameAfterFailure == "Anna")
        #expect(server.member.name == "Anni")
        #expect(account.memberName == "Anni")
    }

    @Test func theNameStaysOnThePhoneAfterARestartOfTheApp() async throws {
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))

        let restarted = Account(server: server, context: context, defaults: defaults)

        #expect(restarted.isSignedIn)
        #expect(restarted.memberName == "Anna")
    }

    @Test func aRenamedPackUploads() async throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))

        try packs.rename(pack, to: "Annas Rudel")
        await account.upload()

        #expect(server.packs[pack.id]?.name == "Annas Rudel")
        #expect(!pack.isWaitingToUpload)
    }

    /// Apple gives the name only once, so a failed sign-in must not lose it.
    @Test func theNameFromAppleStaysWhenTheSignInFails() async throws {
        server.failingOnce = ["signIn"]

        await #expect(throws: FakeServer.Failure.self) {
            try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))
        }
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: nil))

        #expect(server.member.name == "Anna")
    }

    // MARK: Sign-out

    /// The phone of a person who has signed out starts empty, as on a new
    /// install. The pinned areas belong to the phone, so they stay.
    @Test func theSignOutRemovesThePackWithItsDogsAndWalksAndKeepsThePinnedAreas() async throws {
        let bello = try packs.addDog(named: "Bello")
        let walk = Walk(startedAt: .now - 3_600, dogs: [bello], context: context)
        walk.endedAt = .now
        context.insert(CompletedArea(dog: bello, area: 243, completedAt: .now))
        context.insert(CompletedStreet(dog: bello, street: Street.ID(area: 243, name: "Zürcherstrasse"), completedAt: .now))
        context.insert(PinnedArea(area: 243))
        try context.save()
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))

        try await account.signOut()

        #expect(!account.isSignedIn)
        #expect(!server.isSignedIn)
        #expect(account.memberName == "")
        #expect(account.packMembers.isEmpty)
        #expect(account.waitingChanges == 0)
        #expect(try context.fetchAll(Pack.self).isEmpty)
        #expect(try context.fetchAll(Dog.self).isEmpty)
        #expect(try context.fetchAll(Walk.self).isEmpty)
        #expect(try context.fetchAll(WalkDog.self).isEmpty)
        #expect(try context.fetchAll(CompletedArea.self).isEmpty)
        #expect(try context.fetchAll(CompletedStreet.self).isEmpty)
        #expect(try context.fetchAll(PinnedArea.self).map(\.area) == [243])
        #expect(!context.hasChanges)
    }

    @Test func aSignInAfterTheSignOutBringsBackThePackWithItsDogsAndPhotos() async throws {
        let photo = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let bello = try packs.addDog(named: "Bello", photoData: photo)
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))
        // The latest download of the dogs is now later than Bello, by more
        // than the overlap of a download.
        server.passTime(PackDownload.overlap + 1)
        let luna = try packs.addDog(named: "Luna")
        await account.refresh()
        try await account.signOut()

        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: nil))

        let dogs = try context.fetch(Dog.all())
        #expect(Set(dogs.map(\.id)) == [bello.id, luna.id])
        #expect(dogs.first { $0.id == bello.id }?.photoData == photo)
        #expect(account.memberName == "Anna")
        #expect(account.waitingChanges == 0)
    }

    // MARK: Account deletion

    /// The server deletes the pack and everything in it, and the GPS tracks
    /// and photos leave Storage first.
    @Test func theOnlyMemberDeletesTheirAccountAndThePackLeavesTheServerAndThePhone() async throws {
        let bello = try packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        try recordWalk(with: bello)
        context.insert(PinnedArea(area: 243))
        try context.save()
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))
        #expect(server.files.count == 2)

        try await account.deleteAccount()

        #expect(server.isAccountDeleted)
        #expect(server.packs.isEmpty)
        #expect(server.dogs.isEmpty)
        #expect(server.walks.isEmpty)
        #expect(server.walkDogs.isEmpty)
        #expect(server.files.isEmpty)
        #expect(!account.isSignedIn)
        #expect(!server.isSignedIn)
        #expect(try context.fetchAll(Pack.self).isEmpty)
        #expect(try context.fetchAll(Dog.self).isEmpty)
        #expect(try context.fetchAll(Walk.self).isEmpty)
        #expect(try context.fetchAll(PinnedArea.self).map(\.area) == [243])
    }

    /// The walks that the person recorded stay with the dogs, also a walk
    /// that still waited to upload.
    @Test func aMemberOfAPackWithOtherMembersDeletesTheirAccountAndTheirWalksStayWithTheDogs() async throws {
        let bello = try packs.addDog(named: "Bello")
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))
        server.packMembers = [
            PackMember(name: "Anna", isPackOwner: true, isThisPerson: true),
            PackMember(name: "Ben", isPackOwner: false, isThisPerson: false),
        ]
        let walk = try recordWalk(with: bello)
        let packID = try #require(bello.pack?.id)
        #expect(server.walks.isEmpty)

        try await account.deleteAccount()

        #expect(server.isAccountDeleted)
        #expect(server.walks[walk.id] != nil)
        #expect(server.walkDogs.values.map(\.dogID) == [bello.id])
        #expect(server.files[.track(walk: walk.id, pack: packID)] != nil)
        #expect(server.dogs[bello.id] != nil)
        #expect(server.packs[packID] != nil)
        #expect(!account.isSignedIn)
        #expect(try context.fetchAll(Walk.self).isEmpty)
    }

    @Test func aDeletionThatFailsKeepsTheAccountAndThePackOnThePhone() async throws {
        let bello = try packs.addDog(named: "Bello")
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))
        server.isOffline = true

        await #expect(throws: URLError.self) {
            try await account.deleteAccount()
        }

        #expect(!server.isAccountDeleted)
        #expect(account.isSignedIn)
        #expect(try context.fetch(Dog.all()).map(\.id) == [bello.id])
    }

    /// Records an ended walk with a GPS track, and saves it.
    @discardableResult
    private func recordWalk(with dog: Dog) throws -> Walk {
        let start = Date.now - 3_600
        let walk = Walk(startedAt: start, dogs: [dog], context: context)
        walk.store(Track(points: [
            TrackPoint(latitude: 47.4, longitude: 8.4, timestamp: start, horizontalAccuracy: 5),
        ]))
        walk.endedAt = start + 1_800
        try context.save()
        return walk
    }
}
