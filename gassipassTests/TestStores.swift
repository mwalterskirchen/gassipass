//
//  TestStores.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import CoreData
@testable import gassipass

extension Stores {
    /// A second context on the stores, which sees only what was saved.
    func newContext() -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = container.persistentStoreCoordinator
        return context
    }
}

extension NSManagedObjectContext {
    /// All objects of the type, with the values that are in the stores now.
    func fetchAll<Object: NSManagedObject>(
        _ type: Object.Type, where predicate: NSPredicate? = nil
    ) throws -> [Object] {
        let request = NSFetchRequest<Object>(entityName: Object.entity().name!)
        request.predicate = predicate
        request.shouldRefreshRefetchedObjects = true
        return try fetch(request)
    }
}
