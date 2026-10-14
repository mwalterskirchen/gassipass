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
    let server = FakeServer()
    let phone: Phone<FakeServer>

    /// The pack of Anna on the server, with her dog Bello.
    let annasPack = UUID()
    let bello = UUID()

    init() throws {
        server.isSignedIn = true
        phone = try Phone(server: server)
        server.packs[annasPack] = FakeServer.StoredPack(name: "Annas Rudel", createdAt: .now)
        server.dogs[bello] = ServerDog(
            id: bello, packID: annasPack, name: "Bello", photoPath: nil, retiredAt: nil, retirementReason: "",
            deletedAt: nil)
        server.noteChange(of: bello)
        server.invitations["anna-1"] = FakeServer.StoredInvitation(packID: annasPack, packOwnerName: "Anna")
    }

    @Test func aPersonInNoPackSeesThePackAndItsPackOwnerBeforeTheJoin() async throws {
        let invitation = try await phone.account.checkInvitation(token: "anna-1")

        #expect(invitation == Invitation(
            state: .open, packID: annasPack, packName: "Annas Rudel", packOwnerName: "Anna"))
        #expect(server.member.packID == nil)
    }

    @Test func aPersonInNoPackJoinsAndThePhoneDownloadsThePack() async throws {
        let state = try await phone.account.join(token: "anna-1")

        #expect(state == .joined)
        #expect(server.member.packID == annasPack)
        let pack = try #require(try phone.packs.all().first)
        #expect(pack.id == annasPack)
        #expect(pack.dogs?.map(\.name) == ["Bello"])
    }

    @Test func aUsedInvitationJoinsNobody() async throws {
        server.invitations["anna-1"]?.isUsed = true

        let state = try await phone.account.join(token: "anna-1")

        #expect(state == .used)
        #expect(server.member.packID == nil)
        #expect(try phone.packs.all().isEmpty)
    }

    /// The only member of a pack brings their dogs, with their walks and
    /// completed records, and their old pack disappears (ADR 0005).
    @Test func theOnlyMemberOfAPackJoinsAndBringsTheirDogs() async throws {
        let luna = try phone.packs.addDog(named: "Luna", photoData: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        let ownPack = try #require(luna.pack)
        let walk = try phone.recordWalk(dogs: [luna])
        let area = CompletedArea(dog: luna, area: 243, completedAt: .now, context: phone.context)
        try phone.context.save()
        await phone.account.refresh()
        #expect(server.member.packID == ownPack.id)

        let requestsBefore = server.requests.count

        let invitation = try await phone.account.checkInvitation(token: "anna-1")
        let state = try await phone.account.join(token: "anna-1")

        #expect(invitation.state == .open)
        #expect(state == .joined)
        #expect(server.member.packID == annasPack)
        #expect(server.packs[ownPack.id] == nil)
        #expect(server.dogs[luna.id]?.packID == annasPack)
        #expect(server.walks[walk.id]?.packID == annasPack)
        #expect(server.completedAreas[area.id]?.packID == annasPack)
        // The GPS track and the photo stay in the folder of the old pack,
        // where the members of the new pack read them.
        #expect(server.walks[walk.id]?.trackPath == ServerFile.track(walk: walk.id, pack: ownPack.id).path)
        #expect(!server.requests.dropFirst(requestsBefore).contains("uploadFile"))
        #expect(try phone.context.fetchAll(Pack.self).map(\.id) == [annasPack])
        #expect(luna.pack?.id == annasPack)
        #expect(try phone.context.fetch(Dog.all()).map(\.name) == ["Bello", "Luna"])
        #expect(phone.account.waitingChanges == 0)
    }

    /// The GPS track of a walk of a pack that moved stays in the folder of
    /// the old pack. When the member deletes the walk, the track leaves that
    /// folder (#127).
    @Test func aDeletedWalkOfAMovedPackTakesItsTrackOutOfTheFolderOfTheOldPack() async throws {
        let luna = try phone.packs.addDog(named: "Luna")
        let ownPack = try #require(luna.pack)
        let walk = try phone.recordWalk(dogs: [luna])
        await phone.account.refresh()
        _ = try await phone.account.join(token: "anna-1")
        let track = ServerFile.track(walk: walk.id, pack: ownPack.id)
        let trackAfterJoin = server.files[track]

        walk.markDeleted()
        try phone.context.save()
        await phone.account.upload()

        #expect(trackAfterJoin != nil)
        #expect(server.files[track] == nil)
        #expect(server.walks[walk.id]?.trackPath == nil)
        #expect(server.walks[walk.id]?.deletedAt != nil)
        #expect(walk.trackData == nil)
    }

    /// A second phone of the person got the dog of the moved pack with a
    /// download, so it knows the photo by the path in the row. When it
    /// removes the photo, the photo leaves the folder of the old pack (#127).
    @Test func aRemovedPhotoOfADogOfAMovedPackLeavesTheFolderOfTheOldPack() async throws {
        let photo = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let luna = try phone.packs.addDog(named: "Luna", photoData: photo)
        let ownPack = try #require(luna.pack)
        await phone.account.refresh()
        _ = try await phone.account.join(token: "anna-1")
        let second = try Phone(server: server)
        await second.account.refresh()
        let secondLuna = try second.dog(luna.id)
        let photoOnSecondPhone = secondLuna.photoData

        secondLuna.photoData = nil
        secondLuna.noteChange()
        try second.context.save()
        await second.account.upload()

        #expect(photoOnSecondPhone == photo)
        #expect(server.files[.dogPhoto(dog: luna.id, pack: ownPack.id, data: photo)] == nil)
        #expect(server.files.isEmpty)
        #expect(server.dogs[luna.id]?.photoPath == nil)
    }

    /// The pack of the phone failed to upload, so the server does not know
    /// it. The join brings its dogs all the same.
    @Test func aPhoneWithAPackThatHasNotUploadedJoinsAndBringsItsDogs() async throws {
        let luna = try phone.packs.addDog(named: "Luna")
        let ownPack = try #require(luna.pack)
        server.failingOnce = ["createPack"]

        let invitation = try await phone.account.checkInvitation(token: "anna-1")
        let state = try await phone.account.join(token: "anna-1")

        #expect(invitation.state == .open)
        #expect(state == .joined)
        #expect(server.packs[ownPack.id] == nil)
        #expect(server.dogs[luna.id]?.packID == annasPack)
        #expect(try phone.packs.all().map(\.id) == [annasPack])
        #expect(phone.account.packOfAccount == nil)
        #expect(phone.account.waitingChanges == 0)
    }

    @Test func aMemberOfAPackWithOtherMembersCannotJoin() async throws {
        let luna = try phone.packs.addDog(named: "Luna")
        let ownPack = try #require(luna.pack)
        await phone.account.refresh()
        server.packMembers = [
            PackMember(id: UUID(), name: "Ben", isPackOwner: true, isThisPerson: true),
            PackMember(id: UUID(), name: "Carl", isPackOwner: false, isThisPerson: false),
        ]

        let invitation = try await phone.account.checkInvitation(token: "anna-1")
        let state = try await phone.account.join(token: "anna-1")

        #expect(invitation.state == .inOtherPack)
        #expect(state == .inOtherPack)
        #expect(server.member.packID == ownPack.id)
        #expect(server.dogs[luna.id]?.packID == ownPack.id)
        #expect(try phone.packs.all() == [ownPack])
    }

    /// The person joined on another phone, so the server has moved the dogs
    /// already. The second phone asks nothing.
    @Test func theSecondPhoneOfThePersonMovesItsDogsWithoutAQuestion() async throws {
        let luna = try phone.packs.addDog(named: "Luna")
        await phone.account.refresh()
        let second = try Phone(server: server)
        await second.account.refresh()
        let secondLuna = try #require(try second.dogs().first)
        // A walk on the second phone that has not uploaded yet.
        let walk = try second.recordWalk(startedAt: .now - 3_600, dogs: [secondLuna])

        _ = try await phone.account.join(token: "anna-1")
        await second.account.refresh()

        #expect(second.account.packOfAccount == nil)
        #expect(try second.context.fetchAll(Pack.self).map(\.id) == [annasPack])
        #expect(try second.dogs().map(\.name) == ["Bello", "Luna"])
        #expect(secondLuna.id == luna.id)
        #expect(server.walks[walk.id]?.packID == annasPack)
        #expect(second.account.waitingChanges == 0)
    }

    /// The second phone of the person uploads a walk, which the phone that
    /// joins has not downloaded. The phone gets the GPS track of the walk
    /// after the join, from the folder of the old pack.
    @Test func aWalkThatThePhoneDidNotDownloadBeforeTheJoinKeepsItsGPSTrack() async throws {
        try phone.packs.addDog(named: "Luna")
        await phone.account.refresh()
        let second = try Phone(server: server)
        await second.account.refresh()
        let secondLuna = try #require(try second.dogs().first)
        let walk = try second.recordWalk(startedAt: .now - 3_600, dogs: [secondLuna])
        await second.account.upload()

        _ = try await phone.account.join(token: "anna-1")
        await second.account.refresh()

        let joinedWalk = try #require(try phone.context.fetch(FetchDescriptor<Walk>()).first { $0.id == walk.id })
        #expect(joinedWalk.trackData == walk.trackData)
        #expect(walk.trackData != nil)
    }

    /// The account is in the pack of Carl already, and the join into the
    /// pack of Anna fails. The agreement was for the pack of Anna, so the
    /// dogs do not move into the pack of Carl without a question.
    @Test func aFailedJoinMovesNoDogsIntoAnotherPack() async throws {
        let luna = try phone.packs.addDog(named: "Luna")
        let ownPack = try #require(luna.pack)
        let carlsPack = UUID()
        server.packs[carlsPack] = FakeServer.StoredPack(name: "Carls Rudel", createdAt: .now)
        server.member.packID = carlsPack
        server.failingOnce = ["joinPack"]

        await #expect(throws: (any Error).self) {
            try await phone.account.join(token: "anna-1")
        }
        await phone.account.refresh()

        #expect(phone.account.packOfAccount?.id == carlsPack)
        #expect(luna.pack?.id == ownPack.id)
    }

    @Test func theMembersOfThePackLoadWithTheRefresh() async throws {
        server.member.packID = annasPack
        server.packMembers = [
            PackMember(id: UUID(), name: "Anna", isPackOwner: true, isThisPerson: false),
            PackMember(id: UUID(), name: "Ben", isPackOwner: false, isThisPerson: true),
        ]

        await phone.account.refresh()

        #expect(phone.account.packMembers == server.packMembers)
        #expect(!phone.account.isPackOwner)
    }

    @Test func thePackOwnerGetsALinkForEachInvitation() async throws {
        server.member.packID = annasPack
        server.packMembers = [PackMember(id: UUID(), name: "Anna", isPackOwner: true, isThisPerson: true)]
        await phone.account.refresh()

        let first = try await phone.account.makeInvitationLink()
        let second = try await phone.account.makeInvitationLink()

        #expect(phone.account.isPackOwner)
        #expect(first != second)
        let token = try #require(InvitationLink.token(in: first))
        #expect(server.invitations[token]?.packID == annasPack)
    }

    @Test func aPersonWithoutAnAccountIsNoPackOwnerAndSeesNoMembers() async throws {
        server.isSignedIn = false
        let signedOut = Account(server: server, context: phone.context, defaults: emptyDefaults())
        try phone.packs.addDog(named: "Luna")

        await signedOut.refresh()

        #expect(!signedOut.isPackOwner)
        #expect(signedOut.packMembers.isEmpty)
    }
}
