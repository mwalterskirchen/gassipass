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
        packs = Packs(stores: stores, shares: TestShares())
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

    @Test func theFirstLaunchMovesTheDogsFromBeforeThePacksIntoOnePackWithTheirWalksAndCompletedRecords() throws {
        let bello = Dog(name: "Bello", context: context)
        let luna = Dog(name: "Luna", context: context)
        let walk = Walk(startedAt: .now, dogs: [bello, luna], context: context)
        let record = CompletedArea(dog: bello, area: 243, completedAt: .now, context: context)
        try context.save()

        try packs.moveDogsWithoutPack()

        let all = try packs.all()
        #expect(all.count == 1)
        #expect(all.first?.dogs == [bello, luna])
        #expect(bello.walks == [walk])
        #expect(luna.walks == [walk])
        #expect(bello.completedAreas == [record])
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

    @Test func twoFirstPacksOfTheSamePersonMergeIntoThePackThatWasMadeFirst() throws {
        let first = makePack(createdAt: .distantPast + 1, in: context)
        let second = makePack(createdAt: .distantPast + 2, in: context)
        let bello = Dog(name: "Bello", context: context)
        bello.pack = second
        let luna = Dog(name: "Luna", context: context)
        luna.pack = first
        let walk = Walk(startedAt: .now, dogs: [bello, luna], context: context)
        let area = CompletedArea(dog: bello, area: 243, completedAt: .now, context: context)
        let street = CompletedStreet(
            dog: luna, street: Street.ID(area: 243, name: "Bremgartnerstrasse"), completedAt: .now, context: context)
        try context.save()

        try packs.mergeFirstPacks()

        #expect(try stores.newContext().fetchAll(Pack.self).map(\.randomID) == [first.randomID])
        #expect(first.dogs == [bello, luna])
        #expect(bello.walks == [walk])
        #expect(luna.walks == [walk])
        #expect(bello.completedAreas == [area])
        #expect(luna.completedStreets == [street])
        #expect(!context.hasChanges)
    }

    @Test func aNewPackHasACreationDateThatSyncKeepsExactly() throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)

        let seconds = pack.createdAt.timeIntervalSinceReferenceDate
        #expect(seconds == seconds.rounded(.down))
    }

    @Test func everyPhoneKeepsTheSamePackWhenBothPacksWereMadeAtTheSameTime() throws {
        let randomIDs = [UUID().uuidString, UUID().uuidString]
        var kept: [[String]] = []
        // Sync brings the pack of the other phone after the own pack, so the
        // two phones insert the packs in the opposite order.
        for order in [randomIDs, randomIDs.reversed()] {
            let phone = try Stores.inMemory()
            let context = phone.container.viewContext
            for randomID in order {
                let pack = makePack(createdAt: .distantPast, randomID: randomID, in: context)
                Dog(name: "Bello", context: context).pack = pack
                try context.save()
            }

            try Packs(stores: phone, shares: TestShares()).mergeFirstPacks()

            kept.append(try context.fetchAll(Pack.self).map(\.randomID))
        }

        #expect(kept.count == 2)
        #expect(kept.first?.count == 1)
        #expect(kept.first == kept.last)
    }

    @Test func aPackWithAnotherMemberNeverMerges() throws {
        let shared = makePack(createdAt: .distantPast + 1, in: context)
        let first = makePack(createdAt: .distantPast + 2, in: context)
        let second = makePack(createdAt: .distantPast + 3, in: context)
        let bello = Dog(name: "Bello", context: context)
        bello.pack = shared
        let luna = Dog(name: "Luna", context: context)
        luna.pack = second
        try context.save()
        let packs = Packs(stores: stores, shares: TestShares(packsWithOtherMembers: [shared.randomID]))

        try packs.mergeFirstPacks()

        #expect(try packs.all() == [shared, first])
        #expect(bello.pack == shared)
        #expect(luna.pack == first)
    }

    @Test func aJoinedPackNeverMergesWithTheOwnPack() throws {
        let joined = makePack(createdAt: .distantPast + 1, in: context)
        context.assign(joined, to: stores.sharedStore)
        let own = makePack(createdAt: .distantPast + 2, in: context)
        Dog(name: "Bello", context: context).pack = joined
        Dog(name: "Luna", context: context).pack = own
        try context.save()

        try packs.mergeFirstPacks()

        #expect(try packs.all() == [joined, own])
    }

    @Test func theKeptPackTakesTheNameOfTheMergedPackWhenItHasNone() throws {
        let first = makePack(createdAt: .distantPast + 1, in: context)
        let second = makePack(createdAt: .distantPast + 2, in: context)
        second.name = "Bellos Rudel"
        try context.save()

        try packs.mergeFirstPacks()

        #expect(try packs.all() == [first])
        #expect(first.name == "Bellos Rudel")
    }

    @Test func theKeptPackKeepsItsOwnName() throws {
        let first = makePack(createdAt: .distantPast + 1, in: context)
        first.name = "Rudel Dietikon"
        let second = makePack(createdAt: .distantPast + 2, in: context)
        second.name = "Bellos Rudel"
        try context.save()

        try packs.mergeFirstPacks()

        #expect(first.name == "Rudel Dietikon")
    }

    /// A pack of this person, as the first launch of the build with packs
    /// makes it on one of their phones.
    private func makePack(
        createdAt: Date, randomID: String = UUID().uuidString, in context: NSManagedObjectContext
    ) -> Pack {
        let pack = Pack(context: context)
        pack.createdAt = createdAt
        pack.randomID = randomID
        return pack
    }
}

/// The shares of the packs in the tests, which never sync.
private struct TestShares: PackShares {
    /// The random IDs of the packs that have a member besides this person.
    var packsWithOtherMembers: Set<String> = []

    func hasOtherMembers(_ pack: Pack) -> Bool {
        packsWithOtherMembers.contains(pack.randomID)
    }
}
