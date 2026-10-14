//
//  RemoveAndLeaveTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 15.10.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The pack owner removes a member, and a member leaves the pack, through the
/// account, with a server in memory. The phone of the person who is out of
/// the pack keeps nothing of it.
@MainActor
struct RemoveAndLeaveTests {
    let server = FakeServer()
    let phone: PackDownloadTests.Phone

    /// The pack of Anna on the server, with her dog Bello. Ben is a member
    /// of it, and this phone is the phone of Ben.
    let annasPack = UUID()
    let bello = UUID()
    let anna = PackMember(id: UUID(), name: "Anna", isPackOwner: true, isThisPerson: false)
    let ben = PackMember(id: UUID(), name: "Ben", isPackOwner: false, isThisPerson: true)

    init() async throws {
        server.isSignedIn = true
        phone = try PackDownloadTests.Phone(server: server)
        server.packs[annasPack] = FakeServer.StoredPack(name: "Annas Rudel", createdAt: .now)
        server.dogs[bello] = ServerDog(
            id: bello, packID: annasPack, name: "Bello", photoPath: nil, retiredAt: nil, retirementReason: "",
            deletedAt: nil)
        server.noteChange(of: bello)
        server.member = ServerMember(name: "Ben", packID: annasPack)
        server.packMembers = [anna, ben]
        await phone.account.refresh()
    }

    @Test func aMemberWhoIsNotThePackOwnerLeavesAndThePhoneKeepsNothingOfThePack() async throws {
        let walk = try phone.recordWalk(startedAt: .now - 7_200, dogs: [phone.dog(bello)])
        walk.memberName = "Ben"
        try phone.context.save()
        #expect(try phone.packs.all().map(\.id) == [annasPack])

        try await phone.account.leavePack()

        #expect(server.member.packID == nil)
        #expect(try phone.context.fetchAll(Pack.self).isEmpty)
        #expect(try phone.context.fetchAll(Dog.self).isEmpty)
        #expect(try phone.context.fetchAll(Walk.self).isEmpty)
        #expect(try phone.context.fetchAll(WalkDog.self).isEmpty)
        #expect(phone.account.packMembers.isEmpty)
        #expect(phone.account.waitingChanges == 0)
        // The walk of Ben uploaded before he left, and stays with Bello.
        #expect(server.walks[walk.id]?.memberName == "Ben")
        #expect(server.walkDogs.values.map(\.dogID) == [bello])
    }

    @Test func thePackOwnerCannotLeave() async throws {
        server.packMembers = [
            PackMember(id: anna.id, name: "Anna", isPackOwner: true, isThisPerson: true),
            PackMember(id: ben.id, name: "Ben", isPackOwner: false, isThisPerson: false),
        ]
        await phone.account.refresh()

        #expect(!phone.account.canLeavePack)
        await #expect(throws: (any Error).self) {
            try await phone.account.leavePack()
        }
        #expect(server.member.packID == annasPack)
        #expect(try phone.packs.all().map(\.id) == [annasPack])
    }

    @Test func aMemberWhoIsNotThePackOwnerCanLeave() async throws {
        #expect(phone.account.canLeavePack)
        #expect(!phone.account.isPackOwner)
    }

    /// The pack owner removes Ben on her phone. Each phone of Ben deletes
    /// the pack at its next download, also with a change that waits to
    /// upload.
    @Test func eachPhoneOfARemovedMemberDeletesThePackAtItsNextDownload() async throws {
        let second = try PackDownloadTests.Phone(server: server)
        await second.account.refresh()
        try second.recordWalk(startedAt: .now - 7_200, dogs: [second.dog(bello)])
        server.isOffline = true
        await second.account.upload()
        server.isOffline = false

        server.takeAccountOutOfPack()
        await phone.account.refresh()
        await second.account.refresh()

        for phone in [phone, second] {
            #expect(try phone.context.fetchAll(Pack.self).isEmpty)
            #expect(try phone.context.fetchAll(Dog.self).isEmpty)
            #expect(try phone.context.fetchAll(Walk.self).isEmpty)
            #expect(phone.account.waitingChanges == 0)
        }
        #expect(server.walks.isEmpty)
        #expect(server.member.packID == nil)
    }

    @Test func thePackOwnerRemovesAMemberAndKeepsTheWalksOfTheMember() async throws {
        let walk = try phone.recordWalk(startedAt: .now - 7_200, dogs: [phone.dog(bello)])
        walk.memberName = "Ben"
        try phone.context.save()
        await phone.account.upload()
        server.member = ServerMember(name: "Anna", packID: annasPack)
        server.packMembers = [
            PackMember(id: anna.id, name: "Anna", isPackOwner: true, isThisPerson: true),
            PackMember(id: ben.id, name: "Ben", isPackOwner: false, isThisPerson: false),
        ]
        let annasPhone = try PackDownloadTests.Phone(server: server)
        await annasPhone.account.refresh()
        #expect(annasPhone.account.isPackOwner)

        try await annasPhone.account.removeMember(server.packMembers[1])
        await annasPhone.account.refresh()

        #expect(annasPhone.account.packMembers.map(\.name) == ["Anna"])
        #expect(try annasPhone.packs.all().map(\.id) == [annasPack])
        #expect(try annasPhone.walks().map(\.memberName) == ["Ben"])
        #expect(try annasPhone.walks().first?.dogs.map(\.name) == ["Bello"])
    }

    @Test func aMemberWhoIsNotThePackOwnerCannotRemoveAMember() async throws {
        await #expect(throws: (any Error).self) {
            try await phone.account.removeMember(anna)
        }
        #expect(server.packMembers == [anna, ben])
    }

    /// Ben left the pack on his phone, and adds a dog on his second phone,
    /// which still shows the pack of Anna. The second phone deletes the pack
    /// of Anna, and then gets his own pack.
    @Test func aPhoneOfAPersonWhoLeftAndHasANewPackGetsTheNewPack() async throws {
        let second = try PackDownloadTests.Phone(server: server)
        await second.account.refresh()
        try await phone.account.leavePack()
        let rex = try phone.packs.addDog(named: "Rex")
        await phone.account.upload()

        await second.account.refresh()

        #expect(second.account.packOfAccount == nil)
        #expect(try second.packs.all().map(\.id) == [try #require(rex.pack).id])
        #expect(try second.dogs().map(\.name) == ["Rex"])
    }

    /// The deletion of the pack waits until the walk that the phone records
    /// has ended.
    @Test func aPhoneThatRecordsAWalkKeepsThePackUntilTheWalkEnds() async throws {
        let walk = Walk(startedAt: .now - 600, dogs: [try phone.dog(bello)], context: phone.context)
        try phone.context.save()

        server.takeAccountOutOfPack()
        await phone.account.refresh()

        #expect(try phone.packs.all().map(\.id) == [annasPack])

        walk.endedAt = .now
        try phone.context.save()
        await phone.account.refresh()

        #expect(try phone.context.fetchAll(Pack.self).isEmpty)
        #expect(try phone.context.fetchAll(Walk.self).isEmpty)
    }
}
