//
//  PacksTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The pack of the person on the phone, with an in-memory store.
@MainActor
struct PacksTests {
    let container: ModelContainer
    let packs: Packs
    let context: ModelContext

    init() throws {
        container = try LocalStore.inMemory()
        context = container.mainContext
        packs = Packs(context: context)
    }

    @Test func aPersonWhoHasNeverAddedADogHasNoPack() throws {
        #expect(try packs.all().isEmpty)
    }

    @Test func thePersonGetsTheirOwnPackWhenTheyAddTheirFirstDog() throws {
        let bello = try packs.addDog(named: "Bello")

        let all = try packs.all()
        #expect(all.count == 1)
        #expect(bello.pack == all.first)
        #expect(all.first?.dogs == [bello])
    }

    @Test func aSecondDogGoesIntoTheSamePack() throws {
        let bello = try packs.addDog(named: "Bello")
        let luna = try packs.addDog(named: "Luna")

        #expect(try packs.all().count == 1)
        #expect(luna.pack == bello.pack)
    }

    @Test func theFirstLaunchMovesTheDogsFromBeforeThePacksIntoOnePackWithTheirWalksAndCompletedRecords() throws {
        let bello = Dog(name: "Bello", context: context)
        let luna = Dog(name: "Luna", context: context)
        let walk = Walk(startedAt: .now, dogs: [bello, luna], context: context)
        let record = CompletedArea(dog: bello, area: 243, completedAt: .now, context: context)
        try context.save()

        packs.moveDogsWithoutPack()

        let all = try packs.all()
        #expect(all.count == 1)
        #expect(Set(all.first?.dogs ?? []) == [bello, luna])
        #expect(bello.walks == [walk])
        #expect(luna.walks == [walk])
        #expect(bello.completedAreas == [record])
        #expect(!context.hasChanges)
    }

    @Test func theMoveAtLaunchMakesNoPackForAPersonWithNoDogs() throws {
        packs.moveDogsWithoutPack()

        #expect(try packs.all().isEmpty)
    }

    @Test func aDogWithoutPackFromAnOlderBuildGoesIntoTheExistingOwnPack() throws {
        let bello = try packs.addDog(named: "Bello")
        let luna = Dog(name: "Luna", context: context)
        try context.save()

        packs.moveDogsWithoutPack()

        #expect(try packs.all().count == 1)
        #expect(luna.pack == bello.pack)
    }

    @Test func aMemberRenamesThePackAndAnEmptyNameGivesTheDefaultNameBack() throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        let defaultName = packs.shownName(of: pack)

        try packs.rename(pack, to: "  Bellos Rudel ")
        let renamed = packs.shownName(of: pack)
        try packs.rename(pack, to: " ")

        #expect(renamed == "Bellos Rudel")
        #expect(packs.shownName(of: pack) == defaultName)
        #expect(pack.isWaitingToUpload)
        #expect(!context.hasChanges)
    }

    @Test func aWalkShowsTheNameOfTheMemberWhoRecordedIt() throws {
        let bello = try packs.addDog(named: "Bello")
        let walk = Walk(startedAt: .now, dogs: [bello], context: context)
        walk.memberName = "Anna"

        #expect(packs.shownMemberName(of: walk) == "Anna")
    }

    /// An empty name means the pack owner, and without an account the app
    /// does not know the name of the pack owner.
    @Test func aWalkWithAnEmptyMemberNameShowsNoName() throws {
        let bello = try packs.addDog(named: "Bello")
        let walk = Walk(startedAt: .now, dogs: [bello], context: context)

        #expect(packs.shownMemberName(of: walk) == nil)
    }
}
