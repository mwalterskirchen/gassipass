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
    let context: ModelContext
    let bello = Dog(name: "Bello")
    let luna = Dog(name: "Luna")

    init() throws {
        let container = try ModelContainer(
            for: Dog.self, Walk.self, CompletedArea.self, CompletedStreet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context = ModelContext(container)
        context.insert(bello)
        context.insert(luna)
        try context.save()
    }

    @Test func aRetiredDogDoesNotAppearInTheChoiceOfDogsForAWalk() throws {
        luna.retire(on: Date(timeIntervalSinceReferenceDate: 812_000_000), reason: "Old age")
        try context.save()

        let choosable = try context.fetch(FetchDescriptor(predicate: Dog.canJoinWalks))

        #expect(choosable.map(\.name) == ["Bello"])
    }

    @Test func theCollectionOfARetiredDogCanStillBeShown() throws {
        let choice = DogChoice(defaults: UserDefaults(suiteName: "DogTests-\(UUID().uuidString)")!)
        luna.retire(on: .now, reason: "")
        choice.chosenDogID = luna.persistentModelID

        #expect(choice.shownDog(in: [bello, luna]) === luna)
    }

    @Test func deletingAWalkKeepsItsDogsAndTheirCompletedRecords() throws {
        let walk = Walk(startedAt: .now, dogs: [bello, luna])
        context.insert(walk)
        context.insert(CompletedArea(dog: luna, area: 243, completedAt: .now))
        try context.save()

        context.delete(walk)
        try context.save()

        let dogs = try context.fetch(FetchDescriptor<Dog>(sortBy: [SortDescriptor(\.name)]))
        #expect(dogs.map(\.name) == ["Bello", "Luna"])
        #expect(luna.completedAreas?.map(\.area) == [243])
        #expect(luna.walks?.isEmpty == true)
    }

    @Test func removingADogFromAWalkKeepsTheDog() throws {
        let walk = Walk(startedAt: .now, dogs: [bello, luna])
        context.insert(walk)
        try context.save()

        walk.dogs = [bello]
        try context.save()

        let dogs = try context.fetch(FetchDescriptor<Dog>(sortBy: [SortDescriptor(\.name)]))
        #expect(dogs.map(\.name) == ["Bello", "Luna"])
        #expect(luna.walks?.isEmpty == true)
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

    @Test func aDogFromBeforeTheCoatColoursIsApricot() {
        #expect(bello.coatColour == .apricot)
        bello.coatColourName = "brindle"
        #expect(bello.coatColour == .apricot)
    }

    @Test func aNewDogGetsTheFirstCoatColourThatNoOtherDogHas() {
        #expect(CoatColour.forNewDog(besides: []) == .apricot)
        #expect(CoatColour.forNewDog(besides: [.apricot, .red]) == .cream)
        #expect(CoatColour.forNewDog(besides: CoatColour.allCases) == .apricot)
    }
}
