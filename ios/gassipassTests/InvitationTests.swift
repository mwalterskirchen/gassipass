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

    /// The pack of the phone has not uploaded yet, so the server does not
    /// know it. The dogs of the phone first have to move (ADR 0005).
    @Test func aPhoneWithAPackOfItsOwnCannotJoin() async throws {
        let ownPack = try #require(try packs.addDog(named: "Luna").pack)

        let invitation = try await account.checkInvitation(token: "anna-1")
        let state = try await account.join(token: "anna-1")

        #expect(invitation.state == .inOtherPack)
        #expect(state == .inOtherPack)
        #expect(!server.requests.contains("joinPack"))
        #expect(try packs.all() == [ownPack])
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
