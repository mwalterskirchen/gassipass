//
//  StartWalkChoiceTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import CoreData
import Testing
@testable import gassipass

/// Each test uses an in-memory store, so that the dogs have stable
/// identifiers and the tests do not touch the dogs of the app.
@MainActor
struct StartWalkChoiceTests {
    let stores: Stores
    let bello: Dog
    let luna: Dog
    let rex: Dog

    init() throws {
        stores = try Stores.inMemory()
        let context = stores.container.viewContext
        bello = Dog(name: "Bello", context: context)
        luna = Dog(name: "Luna", context: context)
        rex = Dog(name: "Rex", context: context)
        rex.retire(on: .now, reason: "")
        try context.save()
    }

    @Test func withOneDogThatCanJoinWalksTheWalkStartsAtOnce() {
        #expect(StartWalkChoice.onTap(dogs: [bello], shownDog: bello) == .startAtOnce(bello))
    }

    @Test func withMoreDogsTheSheetOpensWithTheShownDogChosen() {
        #expect(
            StartWalkChoice.onTap(dogs: [bello, luna], shownDog: luna)
                == .chooseDogs(chosen: [luna.objectID]))
    }

    @Test func whenTheShownDogIsRetiredTheSheetOpensWithNoDogChosen() {
        #expect(StartWalkChoice.onTap(dogs: [bello, luna, rex], shownDog: rex) == .chooseDogs(chosen: []))
    }

    @Test func whenTheShownDogIsRetiredAndOnlyOneDogCanJoinWalksTheWalkStartsAtOnceWithThatDog() {
        #expect(StartWalkChoice.onTap(dogs: [bello, rex], shownDog: rex) == .startAtOnce(bello))
    }

    /// The walk list shows no dog.
    @Test func withNoShownDogTheSheetOpensWithNoDogChosen() {
        #expect(StartWalkChoice.onTap(dogs: [bello, luna], shownDog: nil) == .chooseDogs(chosen: []))
    }
}
