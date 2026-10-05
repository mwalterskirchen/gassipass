//
//  StoresTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import CoreData
import Foundation
import Testing
@testable import gassipass

/// The in-memory stores that the tests and the demo data use.
@MainActor
struct StoresTests {
    @Test func eachTestGetsEmptyStores() throws {
        let first = try Stores.inMemory()
        let context = first.container.viewContext
        context.insert(NSEntityDescription.insertNewObject(forEntityName: "PinnedArea", into: context))
        try context.save()

        let second = try Stores.inMemory()

        let pins = try second.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "PinnedArea"))
        #expect(pins.isEmpty)
    }

    @Test func anObjectStaysInTheStoreThatItWasAssignedTo() throws {
        let stores = try Stores.inMemory()
        let context = stores.container.viewContext
        let pin = NSEntityDescription.insertNewObject(forEntityName: "PinnedArea", into: context)
        let dog = NSEntityDescription.insertNewObject(forEntityName: "Dog", into: context)
        context.assign(pin, to: stores.privateStore)
        context.assign(dog, to: stores.sharedStore)
        try context.save()

        func entities(in store: NSPersistentStore) throws -> [String] {
            try ["Dog", "PinnedArea"].filter { entity in
                let request = NSFetchRequest<NSManagedObject>(entityName: entity)
                request.affectedStores = [store]
                return try context.count(for: request) > 0
            }
        }
        #expect(try entities(in: stores.privateStore) == ["PinnedArea"])
        #expect(try entities(in: stores.sharedStore) == ["Dog"])
    }
}
