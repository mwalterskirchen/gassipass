//
//  DogTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import SwiftData
import Testing
import UIKit
@testable import gassipass

/// Each test uses an in-memory store, so that it does not touch the dogs and
/// walks of the app.
@MainActor
struct DogTests {
    let container: ModelContainer
    let context: ModelContext
    let bello: Dog
    let luna: Dog

    init() throws {
        container = try LocalStore.inMemory()
        context = container.mainContext
        bello = Dog(name: "Bello", context: context)
        luna = Dog(name: "Luna", context: context)
        try context.save()
    }

    @Test func aRetiredDogDoesNotAppearInTheChoiceOfDogsForAWalk() throws {
        luna.retire(on: Date(timeIntervalSinceReferenceDate: 812_000_000), reason: "Old age")
        try context.save()

        let choosable = try context.fetch(Dog.canJoinWalks())

        #expect(choosable.map(\.name) == ["Bello"])
    }

    @Test func theCollectionOfARetiredDogCanStillBeShown() throws {
        let choice = DogChoice(defaults: UserDefaults(suiteName: "DogTests-\(UUID().uuidString)")!)
        luna.retire(on: .now, reason: "")
        choice.choose(luna.id)

        #expect(choice.shownDog(in: [bello, luna]) === luna)
    }

    /// The same order as the Finder, like the lists of SwiftData before.
    @Test func theDogsAreSortedByNameLikeTheFinder() throws {
        _ = Dog(name: "ärni", context: context)
        _ = Dog(name: "Dog 10", context: context)
        _ = Dog(name: "Dog 9", context: context)
        try context.save()

        #expect(try context.fetch(Dog.all()).map(\.name) == ["ärni", "Bello", "Dog 9", "Dog 10", "Luna"])
    }

    /// The deleted walk stays in the store with its deletion time, so that
    /// the deletion uploads.
    @Test func deletingAWalkKeepsItsDogsAndTheirCompletedRecords() throws {
        let walk = Walk(startedAt: .now, dogs: [bello, luna], context: context)
        _ = CompletedArea(dog: luna, area: 243, completedAt: .now, context: context)
        try context.save()

        walk.markDeleted()
        try context.save()

        let dogs = try context.fetch(Dog.all())
        #expect(dogs.map(\.name) == ["Bello", "Luna"])
        #expect(luna.completedAreas?.map(\.area) == [243])
        #expect(luna.walks.isEmpty)
        #expect(try context.fetch(Walk.ended()).isEmpty)
        #expect(try container.newContext().fetchAll(Walk.self).map { $0.deletedAt != nil } == [true])
    }

    @Test func removingADogFromAWalkKeepsTheDogAndMarksItsRowAsDeleted() throws {
        let walk = Walk(startedAt: .now, dogs: [bello, luna], context: context)
        try context.save()

        walk.changeDogs(to: [bello])
        try context.save()

        let dogs = try context.fetch(Dog.all())
        #expect(dogs.map(\.name) == ["Bello", "Luna"])
        #expect(luna.walks.isEmpty)
        #expect(walk.dogs.map(\.name) == ["Bello"])
        let rows = try container.newContext().fetchAll(WalkDog.self)
        #expect(rows.count == 2)
        #expect(rows.first { $0.dog?.name == "Luna" }?.deletedAt != nil)
    }

    /// Each dog has at most one row in a walk, so that the server has one
    /// row for each dog and walk.
    @Test func aDogThatComesBackToAWalkGetsItsRowBack() throws {
        let walk = Walk(startedAt: .now, dogs: [bello, luna], context: context)
        try context.save()
        walk.changeDogs(to: [bello])
        try context.save()

        walk.changeDogs(to: [bello, luna])
        try context.save()

        #expect(walk.dogs.map(\.name).sorted() == ["Bello", "Luna"])
        let rows = try container.newContext().fetchAll(WalkDog.self)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.deletedAt == nil })
    }

    @Test func aPhotoIsStoredAsASmallJPEG() throws {
        let large = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: .init(for: .init(displayScale: 1)))
            .jpegData(withCompressionQuality: 1) { context in
                UIColor.brown.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
            }

        let stored = try #require(DogPhoto.storedData(from: large))

        let image = try #require(UIImage(data: stored))
        #expect(max(image.size.width, image.size.height) * image.scale == DogPhoto.maxPixels)
        #expect(stored.count < large.count)
    }
}
