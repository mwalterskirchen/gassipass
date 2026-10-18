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
    let server = ObservedServer(FakeServer())
    let phone: Phone<ObservedServer<FakeServer>>

    init() throws {
        phone = try Phone(server: server)
    }

    @Test func aPersonWithoutAnAccountMakesNoRequest() async throws {
        try phone.packs.addDog(named: "Bello")

        await phone.account.upload()

        #expect(!phone.account.isSignedIn)
        #expect(server.requests.isEmpty)
    }

    @Test func theSignInFillsInTheMemberNameAndUploadsThePackWithThePersonAsPackOwner() async throws {
        let pack = try #require(try phone.packs.addDog(named: "Bello").pack)
        try phone.packs.rename(pack, to: "Bellos Rudel")

        try await phone.signIn(givenName: "Anna")

        #expect(phone.account.isSignedIn)
        #expect(phone.account.memberName == "Anna")
        #expect(server.base.member == ServerMember(name: "Anna", packID: pack.id))
        #expect(server.packs == [pack.id: FakeServer.StoredPack(name: "Bellos Rudel", createdAt: pack.createdAt)])
        #expect(!pack.isWaitingToUpload)
        #expect(!phone.context.hasChanges)
    }

    /// Apple gives the name only at the first sign-in of the person.
    @Test func aLaterSignInTakesTheMemberNameFromTheServer() async throws {
        server.base.member.name = "Anna"

        try await phone.signIn()

        #expect(phone.account.memberName == "Anna")
        #expect(!server.requests.contains("renameMember"))
    }

    @Test func aPersonInNoPackUploadsThePackThatStartsWithTheirFirstDog() async throws {
        try await phone.signIn(givenName: "Anna")
        #expect(!server.requests.contains("createPack"))

        let pack = try #require(try phone.packs.addDog(named: "Bello").pack)
        await phone.account.upload()

        #expect(server.base.member.packID == pack.id)
        #expect(server.packs[pack.id]?.name == "")
    }

    /// The dogs of the phone move into the pack of the account only after a
    /// confirmation (ADR 0005). Until then, the pack of the phone waits.
    @Test func aSignInWithAPackOnThePhoneAsksBeforeItsDogsMoveIntoThePackOfTheAccount() async throws {
        let luna = try phone.packs.addDog(named: "Luna")
        let ownPack = try #require(luna.pack)
        let annasPack = UUID()
        server.packs[annasPack] = FakeServer.StoredPack(name: "Annas Rudel", createdAt: .now)
        server.base.member.packID = annasPack

        try await phone.signIn(givenName: "Ben")

        #expect(phone.account.packOfAccount?.name == "Annas Rudel")
        #expect(server.dogs.isEmpty)
        #expect(server.packs.keys.sorted() == [annasPack])
        #expect(try phone.packs.all() == [ownPack])
        #expect(ownPack.isWaitingToUpload)

        await phone.account.moveDogsIntoPackOfAccount()

        #expect(phone.account.packOfAccount == nil)
        #expect(server.dogs[luna.id]?.packID == annasPack)
        #expect(server.packs[annasPack]?.name == "Annas Rudel")
        #expect(try phone.context.fetchAll(Pack.self).map(\.id) == [annasPack])
        #expect(luna.pack?.id == annasPack)
        #expect(phone.account.waitingChanges == 0)
    }

    /// The pack of the phone has uploaded, but the account is now in another
    /// pack, and the server did not move the dogs. After the confirmation,
    /// the dogs upload again into the pack of the account, with their photos.
    @Test func aConfirmedMoveOfAnUploadedPackThatTheServerDidNotMoveUploadsItsDogsAgain() async throws {
        let luna = try phone.packs.addDog(named: "Luna", photoData: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        try await phone.signIn(givenName: "Ben")
        let annasPack = UUID()
        server.packs[annasPack] = FakeServer.StoredPack(name: "Annas Rudel", createdAt: .now)
        server.base.member.packID = annasPack
        await phone.account.refresh()

        await phone.account.moveDogsIntoPackOfAccount()

        #expect(server.dogs[luna.id]?.packID == annasPack)
        #expect(server.files[.dogPhoto(dog: luna.id, pack: annasPack, data: Data([0xFF, 0xD8, 0xFF, 0xE0]))] == luna.photoData)
        #expect(phone.account.waitingChanges == 0)
    }

    /// A restart of the app does not lose the confirmation.
    @Test func aConfirmedMoveHappensAfterAFailure() async throws {
        let luna = try phone.packs.addDog(named: "Luna")
        let annasPack = UUID()
        server.packs[annasPack] = FakeServer.StoredPack(name: "Annas Rudel", createdAt: .now)
        server.base.member.packID = annasPack
        try await phone.signIn(givenName: "Ben")
        server.isOffline = true

        await phone.account.moveDogsIntoPackOfAccount()
        server.isOffline = false
        let restarted = Account(server: server, context: phone.context, defaults: phone.defaults)
        await restarted.refresh()

        #expect(server.dogs[luna.id]?.packID == annasPack)
        #expect(luna.pack?.id == annasPack)
    }

    @Test func theMemberChangesTheirNameAndTheChangeUploads() async throws {
        try await phone.signIn(givenName: "Anna")

        await phone.account.renameMember(to: " Anni ")

        #expect(phone.account.memberName == "Anni")
        #expect(server.base.member.name == "Anni")
    }

    @Test func aNameThatFailedToUploadUploadsWithTheNextUpload() async throws {
        try await phone.signIn(givenName: "Anna")
        server.failingOnce = ["renameMember"]

        await phone.account.renameMember(to: "Anni")
        let nameAfterFailure = server.base.member.name
        await phone.account.upload()

        #expect(nameAfterFailure == "Anna")
        #expect(server.base.member.name == "Anni")
        #expect(phone.account.memberName == "Anni")
    }

    @Test func theNameStaysOnThePhoneAfterARestartOfTheApp() async throws {
        try await phone.signIn(givenName: "Anna")

        let restarted = Account(server: server, context: phone.context, defaults: phone.defaults)

        #expect(restarted.isSignedIn)
        #expect(restarted.memberName == "Anna")
    }

    @Test func aRenamedPackUploads() async throws {
        let pack = try #require(try phone.packs.addDog(named: "Bello").pack)
        try await phone.signIn(givenName: "Anna")

        try phone.packs.rename(pack, to: "Annas Rudel")
        await phone.account.upload()

        #expect(server.packs[pack.id]?.name == "Annas Rudel")
        #expect(!pack.isWaitingToUpload)
    }

    /// Apple gives the name only once, so a failed sign-in must not lose it.
    @Test func theNameFromAppleStaysWhenTheSignInFails() async throws {
        server.failingOnce = ["signIn"]

        await #expect(throws: InjectedFailure.self) {
            try await phone.signIn(givenName: "Anna")
        }
        try await phone.signIn()

        #expect(server.base.member.name == "Anna")
    }

    // MARK: Sign-out

    /// The phone of a person who has signed out starts empty, as on a new
    /// install. The pinned areas belong to the phone, so they stay.
    @Test func theSignOutRemovesThePackWithItsDogsAndWalksAndKeepsThePinnedAreas() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        let walk = Walk(startedAt: .now - 3_600, dogs: [bello], context: phone.context)
        walk.endedAt = .now
        phone.context.insert(CompletedArea(dog: bello, area: 243, completedAt: .now))
        phone.context.insert(CompletedStreet(dog: bello, street: Street.ID(area: 243, name: "Zürcherstrasse"), completedAt: .now))
        phone.context.insert(PinnedArea(area: 243))
        try phone.context.save()
        try await phone.signIn(givenName: "Anna")

        try await phone.account.signOut()

        #expect(!phone.account.isSignedIn)
        #expect(!server.isSignedIn)
        #expect(phone.account.memberName == "")
        #expect(phone.account.packMembers.isEmpty)
        #expect(phone.account.waitingChanges == 0)
        #expect(try phone.context.fetchAll(Pack.self).isEmpty)
        #expect(try phone.context.fetchAll(Dog.self).isEmpty)
        #expect(try phone.context.fetchAll(Walk.self).isEmpty)
        #expect(try phone.context.fetchAll(WalkDog.self).isEmpty)
        #expect(try phone.context.fetchAll(CompletedArea.self).isEmpty)
        #expect(try phone.context.fetchAll(CompletedStreet.self).isEmpty)
        #expect(try phone.context.fetchAll(PinnedArea.self).map(\.area) == [243])
        #expect(!phone.context.hasChanges)
    }

    /// The settings cannot open during a walk, but the walk must never lose
    /// its pack.
    @Test func nobodySignsOutOrDeletesTheirAccountDuringAWalk() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        _ = Walk(startedAt: .now, dogs: [bello], context: phone.context)
        try phone.context.save()
        try await phone.signIn(givenName: "Anna")

        await #expect(throws: AccountError.walkIsRecorded) {
            try await phone.account.signOut()
        }
        await #expect(throws: AccountError.walkIsRecorded) {
            try await phone.account.deleteAccount()
        }

        #expect(phone.account.isSignedIn)
        #expect(!server.isAccountDeleted)
        #expect(try phone.context.fetch(Dog.all()).map(\.id) == [bello.id])
    }

    @Test func aSignInAfterTheSignOutBringsBackThePackWithItsDogsAndPhotos() async throws {
        let photo = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let bello = try phone.packs.addDog(named: "Bello", photoData: photo)
        try await phone.signIn(givenName: "Anna")
        // The latest download of the dogs is now later than Bello, by more
        // than the overlap of a download.
        server.base.passTime(PackDownload.overlap + 1)
        let luna = try phone.packs.addDog(named: "Luna")
        await phone.account.refresh()
        try await phone.account.signOut()

        try await phone.signIn()

        let dogs = try phone.context.fetch(Dog.all())
        #expect(Set(dogs.map(\.id)) == [bello.id, luna.id])
        #expect(dogs.first { $0.id == bello.id }?.photoData == photo)
        #expect(phone.account.memberName == "Anna")
        #expect(phone.account.waitingChanges == 0)
    }

    // MARK: Account deletion

    /// The server deletes the pack and everything in it, and the GPS tracks
    /// and photos leave Storage first.
    @Test func theOnlyMemberDeletesTheirAccountAndThePackLeavesTheServerAndThePhone() async throws {
        let bello = try phone.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        try phone.recordWalk(dogs: [bello])
        phone.context.insert(PinnedArea(area: 243))
        try phone.context.save()
        try await phone.signIn(givenName: "Anna")
        #expect(server.files.count == 2)

        try await phone.account.deleteAccount()

        #expect(server.isAccountDeleted)
        #expect(server.packs.isEmpty)
        #expect(server.dogs.isEmpty)
        #expect(server.walks.isEmpty)
        #expect(server.walkDogs.isEmpty)
        #expect(server.files.isEmpty)
        #expect(!phone.account.isSignedIn)
        #expect(!server.isSignedIn)
        #expect(try phone.context.fetchAll(Pack.self).isEmpty)
        #expect(try phone.context.fetchAll(Dog.self).isEmpty)
        #expect(try phone.context.fetchAll(Walk.self).isEmpty)
        #expect(try phone.context.fetchAll(PinnedArea.self).map(\.area) == [243])
    }

    /// The walks that the person recorded stay with the dogs, also a walk
    /// that still waited to upload.
    @Test func aMemberOfAPackWithOtherMembersDeletesTheirAccountAndTheirWalksStayWithTheDogs() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        try await phone.signIn(givenName: "Anna")
        server.base.packMembers = [
            PackMember(id: UUID(), name: "Anna", isPackOwner: true, isThisPerson: true),
            PackMember(id: UUID(), name: "Ben", isPackOwner: false, isThisPerson: false),
        ]
        let walk = try phone.recordWalk(dogs: [bello])
        let packID = try #require(bello.pack?.id)
        #expect(server.walks.isEmpty)

        try await phone.account.deleteAccount()

        #expect(server.isAccountDeleted)
        #expect(server.walks[walk.id] != nil)
        #expect(server.walkDogs.values.map(\.dogID) == [bello.id])
        #expect(server.files[.track(walk: walk.id, pack: packID)] != nil)
        #expect(server.dogs[bello.id] != nil)
        #expect(server.packs[packID] != nil)
        #expect(!phone.account.isSignedIn)
        #expect(try phone.context.fetchAll(Walk.self).isEmpty)
    }

    @Test func aDeletionThatFailsKeepsTheAccountAndThePackOnThePhone() async throws {
        let bello = try phone.packs.addDog(named: "Bello")
        try await phone.signIn(givenName: "Anna")
        server.isOffline = true

        await #expect(throws: URLError.self) {
            try await phone.account.deleteAccount()
        }

        #expect(!server.isAccountDeleted)
        #expect(phone.account.isSignedIn)
        #expect(try phone.context.fetch(Dog.all()).map(\.id) == [bello.id])
    }

    /// The settings show the account until the deletion has ended, so that
    /// a failure can show there.
    @Test func thePersonStaysSignedInWhileTheDeletionRuns() async throws {
        try await phone.signIn(givenName: "Anna")
        var wasSignedIn: Bool?
        server.beforeRequest = { name in
            if name == "deleteAccount" {
                wasSignedIn = phone.account.isSignedIn
            }
        }

        try await phone.account.deleteAccount()

        #expect(wasSignedIn == true)
        #expect(!phone.account.isSignedIn)
    }

    /// The files of the pack have left Storage, but the account is still
    /// there. The next upload brings the files back.
    @Test func theFilesUploadAgainWhenTheDeletionFailsAfterThem() async throws {
        let bello = try phone.packs.addDog(named: "Bello", photoData: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        let walk = try phone.recordWalk(dogs: [bello])
        let packID = try #require(bello.pack?.id)
        try await phone.signIn(givenName: "Anna")
        server.failingOnce = ["deleteAccount"]

        await #expect(throws: InjectedFailure.self) {
            try await phone.account.deleteAccount()
        }
        #expect(server.files.isEmpty)
        await phone.account.upload()

        #expect(phone.account.isSignedIn)
        #expect(server.files[.track(walk: walk.id, pack: packID)] == walk.trackData)
        #expect(server.files[.dogPhoto(dog: bello.id, pack: packID, data: try #require(bello.photoData))] == bello.photoData)
    }
}
