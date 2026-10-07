//
//  DogChoiceTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

/// Each test uses its own user defaults and an in-memory store, so that it
/// does not touch the choice or the dogs of the app.
@MainActor
struct DogChoiceTests {
    let defaults = UserDefaults(suiteName: "DogChoiceTests-\(UUID().uuidString)")!
    let container: ModelContainer
    let bello: Dog
    let luna: Dog

    init() throws {
        container = try LocalStore.inMemory()
        let context = container.mainContext
        bello = Dog(name: "Bello", context: context)
        luna = Dog(name: "Luna", context: context)
        try context.save()
    }

    @Test func theChosenDogIsStillChosenAfterTheAppStartsAgain() {
        DogChoice(defaults: defaults).choose(luna.id)

        #expect(DogChoice(defaults: defaults).shownDog(in: [bello, luna]) === luna)
    }

    @Test func whenTheChosenDogIsNotInTheListAnyMoreTheFirstDogShows() {
        DogChoice(defaults: defaults).choose(luna.id)

        #expect(DogChoice(defaults: defaults).shownDog(in: [bello]) === bello)
    }
}
