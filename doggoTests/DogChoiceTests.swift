//
//  DogChoiceTests.swift
//  doggoTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import SwiftData
import Testing
@testable import doggo

/// Each test uses its own user defaults and an in-memory store, so that it
/// does not touch the choice or the dogs of the app.
@MainActor
struct DogChoiceTests {
    let defaults = UserDefaults(suiteName: "DogChoiceTests-\(UUID().uuidString)")!
    let context: ModelContext
    let bello = Dog(name: "Bello")
    let luna = Dog(name: "Luna")

    init() throws {
        let container = try ModelContainer(
            for: Dog.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context = ModelContext(container)
        context.insert(bello)
        context.insert(luna)
        try context.save()
    }

    @Test func theChosenDogIsStillChosenAfterTheAppStartsAgain() {
        DogChoice(defaults: defaults).chosenDogID = luna.persistentModelID

        #expect(DogChoice(defaults: defaults).shownDog(in: [bello, luna]) === luna)
    }

    @Test func whenTheChosenDogIsNotInTheListAnyMoreTheFirstDogShows() {
        DogChoice(defaults: defaults).chosenDogID = luna.persistentModelID

        #expect(DogChoice(defaults: defaults).shownDog(in: [bello]) === bello)
    }
}
