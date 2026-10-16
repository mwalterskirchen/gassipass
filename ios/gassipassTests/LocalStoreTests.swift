//
//  LocalStoreTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 12.10.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The migration of the local store to the current schema.
@MainActor
struct LocalStoreTests {
    let url = URL.temporaryDirectory.appending(path: "LocalStoreTests \(UUID().uuidString).store")

    @Test func aStoreOfTheFirstSchemaOpensWithItsRowsAndGetsTheStoredCollections() throws {
        let dogID: UUID
        do {
            let old = try ModelContainer(
                for: Schema(versionedSchema: LocalSchemaV1.self),
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let dog = LocalSchemaV1.Dog(name: "Bello")
            old.mainContext.insert(dog)
            try old.mainContext.save()
            dogID = dog.id
        }

        let container = try LocalStore.container(at: url)

        let context = container.mainContext
        #expect(try context.fetch(FetchDescriptor<Dog>()).map(\.id) == [dogID])
        #expect(try context.fetchCount(FetchDescriptor<WalkedSegment>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CollectionBuild>()) == 0)
    }

    @Test func aStoreOfTheSecondSchemaOpensWithItsRecordsAndGetsTheAreaSteps() throws {
        let dogID: UUID
        do {
            let old = try ModelContainer(
                for: Schema(versionedSchema: LocalSchemaV2.self),
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let dog = LocalSchemaV1.Dog(name: "Bello")
            old.mainContext.insert(dog)
            old.mainContext.insert(LocalSchemaV1.CompletedArea(dog: dog, area: 243, completedAt: .now))
            try old.mainContext.save()
            dogID = dog.id
        }

        let container = try LocalStore.container(at: url)

        let context = container.mainContext
        let dog = try #require(try context.fetch(FetchDescriptor<Dog>()).first)
        #expect(dog.id == dogID)
        #expect(dog.completedAreas?.map(\.area) == [243])
        _ = AreaStep(dog: dog, area: 243, step: .half, reachedAt: .now, context: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<AreaStep>()).map(\.dogID) == [dogID])
    }

    @Test func aStoreOfTheThirdSchemaOpensWithItsRowsAndGetsTheHomeBaseAndTheRingStamps() throws {
        let dogID: UUID
        do {
            let old = try ModelContainer(
                for: Schema(versionedSchema: LocalSchemaV3.self),
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let pack = LocalSchemaV1.Pack(name: "Rudel", createdAt: .now)
            let dog = LocalSchemaV1.Dog(name: "Bello")
            dog.pack = pack
            old.mainContext.insert(dog)
            old.mainContext.insert(LocalSchemaV3.AreaStep(dogID: dog.id, area: 243, step: 25, reachedAt: .now))
            try old.mainContext.save()
            dogID = dog.id
        }

        let container = try LocalStore.container(at: url)

        let context = container.mainContext
        let pack = try #require(try Pack.ofThisPhone(in: context))
        #expect(pack.name == "Rudel")
        #expect(pack.homeBase == nil)
        #expect(pack.dogs?.map(\.id) == [dogID])
        #expect(try context.fetch(FetchDescriptor<AreaStep>()).map(\.area) == [243])
        let home = HomeBase(latitude: 47.4, longitude: 8.4)
        pack.setHomeBase(home, at: .now)
        _ = CompletedRing(
            dogID: dogID, ring: Ring(number: 1, centre: home), completedAt: .now, context: context)
        try context.save()
        let stored = container.newContext()
        #expect(try Pack.ofThisPhone(in: stored)?.homeBase == home)
        #expect(try stored.fetch(FetchDescriptor<CompletedRing>()).map(\.ring) == [Ring(number: 1, centre: home)])
    }
}
