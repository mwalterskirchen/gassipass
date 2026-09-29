//
//  StartWalkChoiceTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

/// Each test uses an in-memory store, so that the dogs have stable
/// identifiers and the tests do not touch the dogs of the app.
@MainActor
struct StartWalkChoiceTests {
    let context: ModelContext
    let bello = Dog(name: "Bello")
    let luna = Dog(name: "Luna")
    let rex = Dog(name: "Rex")

    init() throws {
        let container = try ModelContainer(
            for: Dog.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context = ModelContext(container)
        context.insert(bello)
        context.insert(luna)
        context.insert(rex)
        rex.retire(on: .now, reason: "")
        try context.save()
    }

    @Test func withOneDogThatCanJoinWalksTheWalkStartsAtOnce() {
        #expect(StartWalkChoice.onTap(dogs: [bello], shownDog: bello) == .startAtOnce(bello))
    }

    @Test func withMoreDogsTheSheetOpensWithTheShownDogChosen() {
        #expect(
            StartWalkChoice.onTap(dogs: [bello, luna], shownDog: luna)
                == .chooseDogs(chosen: [luna.persistentModelID]))
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
