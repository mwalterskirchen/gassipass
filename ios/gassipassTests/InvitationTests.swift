//
//  InvitationTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 14.10.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The invitation to a pack and the join, through the account, with a
/// server in memory.
@MainActor
struct InvitationTests {
    let container: ModelContainer
    let context: ModelContext
    let packs: Packs
    let server = FakeServer()
    let account: Account

    /// The pack of Anna on the server, with her dog Bello.
    let annasPack = UUID()
    let bello = UUID()

    init() throws {
        container = try LocalStore.inMemory()
        context = container.mainContext
        packs = Packs(context: context)
        server.isSignedIn = true
        account = Account(
            server: server, context: context, defaults: UserDefaults(suiteName: "InvitationTests-\(UUID().uuidString)")!)
        server.packs[annasPack] = FakeServer.StoredPack(name: "Annas Rudel", createdAt: .now)
        server.dogs[bello] = ServerDog(
            id: bello, packID: annasPack, name: "Bello", photoPath: nil, retiredAt: nil, retirementReason: "",
            deletedAt: nil)
        server.noteChange(of: bello)
        server.invitations["anna-1"] = FakeServer.StoredInvitation(packID: annasPack, packOwnerName: "Anna")
    }

    @Test func aPersonInNoPackSeesThePackAndItsPackOwnerBeforeTheJoin() async throws {
        let invitation = try await account.checkInvitation(token: "anna-1")

        #expect(invitation == Invitation(
            state: .open, packID: annasPack, packName: "Annas Rudel", packOwnerName: "Anna"))
        #expect(server.member.packID == nil)
    }

    @Test func aPersonInNoPackJoinsAndThePhoneDownloadsThePack() async throws {
        let state = try await account.join(token: "anna-1")

        #expect(state == .joined)
        #expect(server.member.packID == annasPack)
        let pack = try #require(try packs.all().first)
        #expect(pack.id == annasPack)
        #expect(pack.dogs?.map(\.name) == ["Bello"])
    }

    @Test func aUsedInvitationJoinsNobody() async throws {
        server.invitations["anna-1"]?.isUsed = true

        let state = try await account.join(token: "anna-1")

        #expect(state == .used)
        #expect(server.member.packID == nil)
        #expect(try packs.all().isEmpty)
    }

    /// The only member of a pack brings their dogs, with their walks and
    /// completed records, and their old pack disappears (ADR 0005).
    @Test func theOnlyMemberOfAPackJoinsAndBringsTheirDogs() async throws {
        let luna = try packs.addDog(named: "Luna", photoData: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        let ownPack = try #require(luna.pack)
        let walk = try recordWalk(with: luna)
        let area = CompletedArea(dog: luna, area: 243, completedAt: .now, context: context)
        try context.save()
        await account.refresh()
        #expect(server.member.packID == ownPack.id)

        let invitation = try await account.checkInvitation(token: "anna-1")
        let state = try await account.join(token: "anna-1")

        #expect(invitation.state == .open)
        #expect(state == .joined)
        #expect(server.member.packID == annasPack)
        #expect(server.packs[ownPack.id] == nil)
        #expect(server.dogs[luna.id]?.packID == annasPack)
        #expect(server.walks[walk.id]?.packID == annasPack)
        #expect(server.completedAreas[area.id]?.packID == annasPack)
        // The GPS track and the photo upload again into the folder of the
        // new pack.
        #expect(server.files[.track(walk: walk.id, pack: annasPack)] == walk.trackData)
        #expect(server.files[.dogPhoto(dog: luna.id, pack: annasPack)] == luna.photoData)
        #expect(server.walks[walk.id]?.trackPath == ServerFile.track(walk: walk.id, pack: annasPack).path)
        #expect(try context.fetchAll(Pack.self).map(\.id) == [annasPack])
        #expect(luna.pack?.id == annasPack)
        #expect(try context.fetch(Dog.all()).map(\.name) == ["Bello", "Luna"])
        #expect(account.waitingChanges == 0)
    }

    /// A save during the join starts an upload, which still sees the old
    /// pack. The GPS track and the photo upload again all the same.
    @Test func anUploadDuringTheJoinKeepsTheFilesUploadingAgain() async throws {
        let luna = try packs.addDog(named: "Luna", photoData: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        let walk = try recordWalk(with: luna)
        await account.refresh()
        server.duringJoin = { [account] in
            await account.upload()
        }

        let state = try await account.join(token: "anna-1")

        #expect(state == .joined)
        #expect(server.files[.track(walk: walk.id, pack: annasPack)] == walk.trackData)
        #expect(server.files[.dogPhoto(dog: luna.id, pack: annasPack)] == luna.photoData)
    }

    /// The pack of the phone failed to upload, so the server does not know
    /// it. The join brings its dogs all the same.
    @Test func aPhoneWithAPackThatHasNotUploadedJoinsAndBringsItsDogs() async throws {
        let luna = try packs.addDog(named: "Luna")
        let ownPack = try #require(luna.pack)
        server.failingOnce = ["createPack"]

        let invitation = try await account.checkInvitation(token: "anna-1")
        let state = try await account.join(token: "anna-1")

        #expect(invitation.state == .open)
        #expect(state == .joined)
        #expect(server.packs[ownPack.id] == nil)
        #expect(server.dogs[luna.id]?.packID == annasPack)
        #expect(try packs.all().map(\.id) == [annasPack])
        #expect(account.packOfAccount == nil)
        #expect(account.waitingChanges == 0)
    }

    @Test func aMemberOfAPackWithOtherMembersCannotJoin() async throws {
        let luna = try packs.addDog(named: "Luna")
        let ownPack = try #require(luna.pack)
        await account.refresh()
        server.packMembers = [
            PackMember(name: "Ben", isPackOwner: true, isThisPerson: true),
            PackMember(name: "Carl", isPackOwner: false, isThisPerson: false),
        ]

        let invitation = try await account.checkInvitation(token: "anna-1")
        let state = try await account.join(token: "anna-1")

        #expect(invitation.state == .inOtherPack)
        #expect(state == .inOtherPack)
        #expect(server.member.packID == ownPack.id)
        #expect(server.dogs[luna.id]?.packID == ownPack.id)
        #expect(try packs.all() == [ownPack])
    }

    /// The person joined on another phone, so the server has moved the dogs
    /// already. The second phone asks nothing.
    @Test func theSecondPhoneOfThePersonMovesItsDogsWithoutAQuestion() async throws {
        let luna = try packs.addDog(named: "Luna")
        await account.refresh()
        let secondContainer = try LocalStore.inMemory()
        let secondContext = secondContainer.mainContext
        let second = Account(
            server: server, context: secondContext,
            defaults: UserDefaults(suiteName: "InvitationTests-\(UUID().uuidString)")!)
        await second.refresh()
        let secondLuna = try #require(try secondContext.fetch(Dog.all()).first)
        // A walk on the second phone that has not uploaded yet.
        let walk = Walk(startedAt: .now - 3_600, dogs: [secondLuna], context: secondContext)
        walk.store(Track())
        walk.endedAt = .now
        try secondContext.save()

        _ = try await account.join(token: "anna-1")
        await second.refresh()

        #expect(second.packOfAccount == nil)
        #expect(try secondContext.fetchAll(Pack.self).map(\.id) == [annasPack])
        #expect(try secondContext.fetch(Dog.all()).map(\.name) == ["Bello", "Luna"])
        #expect(secondLuna.id == luna.id)
        #expect(server.walks[walk.id]?.packID == annasPack)
        #expect(second.waitingChanges == 0)
    }

    @Test func theMembersOfThePackLoadWithTheRefresh() async throws {
        server.member.packID = annasPack
        server.packMembers = [
            PackMember(name: "Anna", isPackOwner: true, isThisPerson: false),
            PackMember(name: "Ben", isPackOwner: false, isThisPerson: true),
        ]

        await account.refresh()

        #expect(account.packMembers == server.packMembers)
        #expect(!account.isPackOwner)
    }

    @Test func thePackOwnerGetsALinkForEachInvitation() async throws {
        server.member.packID = annasPack
        server.packMembers = [PackMember(name: "Anna", isPackOwner: true, isThisPerson: true)]
        await account.refresh()

        let first = try await account.makeInvitationLink()
        let second = try await account.makeInvitationLink()

        #expect(account.isPackOwner)
        #expect(first != second)
        let token = try #require(InvitationLink.token(in: first))
        #expect(server.invitations[token]?.packID == annasPack)
    }

    /// Records an ended walk with the dog, and saves it.
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

    @Test func aPersonWithoutAnAccountIsNoPackOwnerAndSeesNoMembers() async throws {
        server.isSignedIn = false
        let account = Account(
            server: server, context: context, defaults: UserDefaults(suiteName: "InvitationTests-\(UUID().uuidString)")!)
        try packs.addDog(named: "Luna")

        await account.refresh()

        #expect(!account.isPackOwner)
        #expect(account.packMembers.isEmpty)
    }
}
