//
//  PacksTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import CoreData
import Foundation
import Testing
@testable import gassipass

/// The packs of the person on the phone, with an in-memory private store and
/// an in-memory shared store that never sync.
@MainActor
struct PacksTests {
    let stores: Stores
    let packs: Packs
    let context: NSManagedObjectContext

    init() throws {
        stores = try Stores.inMemory()
        packs = Packs(stores: stores)
        context = stores.container.viewContext
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

    @Test func aDogGoesIntoTheStoreOfItsPack() throws {
        let own = try packs.addDog(named: "Bello").pack
        let joined = Pack(context: context)
        context.assign(joined, to: stores.sharedStore)

        let luna = try packs.addDog(named: "Luna", to: joined)
        let rex = try packs.addDog(named: "Rex", to: own)

        #expect(luna.objectID.persistentStore == stores.sharedStore)
        #expect(rex.objectID.persistentStore == stores.privateStore)
    }

    @Test func theFirstLaunchMovesTheDogsFromBeforeThePacksIntoOnePackWithTheirWalksAndStamps() throws {
        let bello = Dog(name: "Bello", context: context)
        let luna = Dog(name: "Luna", context: context)
        let walk = Walk(startedAt: .now, dogs: [bello, luna], context: context)
        let stamp = CompletedArea(dog: bello, area: 243, completedAt: .now, context: context)
        try context.save()

        try packs.moveDogsWithoutPack()

        let all = try packs.all()
        #expect(all.count == 1)
        #expect(all.first?.dogs == [bello, luna])
        #expect(bello.walks == [walk])
        #expect(luna.walks == [walk])
        #expect(bello.completedAreas == [stamp])
    }

    @Test func theMoveAtLaunchMakesNoPackForAPersonWithNoDogs() throws {
        try packs.moveDogsWithoutPack()

        #expect(try packs.all().isEmpty)
    }

    @Test func aDogWithoutPackFromAnOlderBuildGoesIntoTheExistingOwnPack() throws {
        let bello = try packs.addDog(named: "Bello")
        try packs.moveDogsWithoutPack()
        let luna = Dog(name: "Luna", context: context)
        try context.save()

        try packs.moveDogsWithoutPack()

        #expect(try packs.all().count == 1)
        #expect(luna.pack == bello.pack)
    }

    @Test func aMemberRenamesThePackAndAnEmptyNameGivesTheDefaultNameBack() throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        let defaultName = pack.shownName

        try packs.rename(pack, to: "  Bellos Rudel ")
        let renamed = pack.shownName
        try packs.rename(pack, to: " ")

        #expect(renamed == "Bellos Rudel")
        #expect(pack.shownName == defaultName)
        #expect(!context.hasChanges)
    }
}
