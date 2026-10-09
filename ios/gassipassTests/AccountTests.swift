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

    /// The dogs of the phone first have to move into the pack of the account
    /// (ADR 0005), so the pack of the phone waits.
    @Test func thePackOfThePhoneWaitsWhenTheAccountIsInAnotherPack() async throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        server.member.packID = UUID()

        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: "Anna"))

        #expect(server.packs.isEmpty)
        #expect(pack.isWaitingToUpload)
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
}
