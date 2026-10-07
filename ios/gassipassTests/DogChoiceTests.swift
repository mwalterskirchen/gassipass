//
//  DogChoiceTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import CoreData
import Testing
@testable import gassipass

/// Each test uses its own user defaults and an in-memory store, so that it
/// does not touch the choice or the dogs of the app.
@MainActor
struct DogChoiceTests {
    let defaults = UserDefaults(suiteName: "DogChoiceTests-\(UUID().uuidString)")!
    let stores: Stores
    let bello: Dog
    let luna: Dog

    init() throws {
        stores = try Stores.inMemory()
        let context = stores.container.viewContext
        bello = Dog(name: "Bello", context: context)
        luna = Dog(name: "Luna", context: context)
        try context.save()
    }

    @Test func theChosenDogIsStillChosenAfterTheAppStartsAgain() {
        DogChoice(defaults: defaults).choose(luna.objectID)

        #expect(DogChoice(defaults: defaults).shownDog(in: [bello, luna]) === luna)
    }

    @Test func whenTheChosenDogIsNotInTheListAnyMoreTheFirstDogShows() {
        DogChoice(defaults: defaults).choose(luna.objectID)

        #expect(DogChoice(defaults: defaults).shownDog(in: [bello]) === bello)
    }

    /// The builds with SwiftData stored the choice as a JSON-encoded
    /// `PersistentIdentifier`. Core Data opens the same store, so the URI in
    /// it still names the same dog.
    @Test func theChoiceOfABuildWithSwiftDataIsStillChosen() throws {
        let uri = luna.objectID.uriRepresentation().absoluteString
        let json = #"{"implementation":{"primaryKey":"p2","isTemporary":false,"entityName":"Dog","uriRepresentation":"\#(uri)"}}"#
        defaults.set(Data(json.utf8), forKey: "chosenDogID")

        #expect(DogChoice(defaults: defaults).shownDog(in: [bello, luna]) === luna)
        #expect(defaults.object(forKey: "chosenDogID") == nil)
        #expect(DogChoice(defaults: defaults).shownDog(in: [bello, luna]) === luna)
    }
}
