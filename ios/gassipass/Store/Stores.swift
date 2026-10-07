//
//  Stores.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import CloudKit
import CoreData

/// The Core Data stack of the app, with two stores (ADR 0004). The private
/// store holds the packs of the person on this phone and the pinned areas,
/// and syncs with the private database of their iCloud account. The shared
/// store holds the packs that the person joined, and syncs with the shared
/// database.
///
/// The model follows the CloudKit rules: every attribute has a default value,
/// every relationship is optional and has an inverse, and nothing is unique.
/// Core Data has no autosave, so the app saves each change itself.
final class Stores {
    let container: NSPersistentCloudKitContainer
    let privateStore: NSPersistentStore
    let sharedStore: NSPersistentStore

    nonisolated static let cloudKitContainerIdentifier = "iCloud.ch.mwalterskirchen.gassipass"

    /// The model, loaded once, because Core Data expects one model for each
    /// entity class in a process.
    static let model: NSManagedObjectModel = {
        guard let url = Bundle(for: Stores.self).url(forResource: "gassipass", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url)
        else {
            fatalError("The Core Data model is missing from the app")
        }
        return model
    }()

    /// The stores of the app in Application Support, which sync with iCloud.
    /// Without an account or a network they work as local stores, and sync
    /// starts when they are back.
    static func app() throws -> Stores {
        // A new install has no Application Support folder yet.
        try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        return try Stores(folder: .applicationSupportDirectory, syncsWithCloudKit: true)
    }

    /// Empty stores in memory that never sync, for the tests and the demo data.
    static func inMemory() throws -> Stores {
        // Two SQLite stores cannot both use /dev/null, so they use the
        // in-memory store type, with a different URL each.
        func memoryStore(_ name: String) -> NSPersistentStoreDescription {
            let description = NSPersistentStoreDescription(url: URL(string: "memory://\(name)")!)
            description.type = NSInMemoryStoreType
            return description
        }
        return try Stores(privateStore: memoryStore("private"), sharedStore: memoryStore("shared"), syncsWithCloudKit: false)
    }

    /// The file of the private store in the folder. It is the file that
    /// SwiftData wrote, so that Core Data opens the dogs, walks, completed
    /// records and pinned areas that are on the phone.
    static func privateStoreURL(in folder: URL) -> URL {
        folder.appending(path: "default.store")
    }

    private static func sharedStoreURL(in folder: URL) -> URL {
        folder.appending(path: "shared.store")
    }

    /// Opens the stores in the folder, or creates them.
    convenience init(folder: URL, syncsWithCloudKit: Bool) throws {
        try self.init(
            privateStore: NSPersistentStoreDescription(url: Self.privateStoreURL(in: folder)),
            sharedStore: NSPersistentStoreDescription(url: Self.sharedStoreURL(in: folder)),
            syncsWithCloudKit: syncsWithCloudKit)
    }

    private init(
        privateStore: NSPersistentStoreDescription, sharedStore: NSPersistentStoreDescription,
        syncsWithCloudKit: Bool
    ) throws {
        for (description, scope) in [(privateStore, CKDatabase.Scope.private), (sharedStore, .shared)] {
            // SwiftData tracked the history of the store, and Core Data opens
            // such a store read-only without it. CloudKit needs it too.
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            if syncsWithCloudKit {
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerIdentifier)
                options.databaseScope = scope
                description.cloudKitContainerOptions = options
            } else {
                description.cloudKitContainerOptions = nil
            }
        }
        container = NSPersistentCloudKitContainer(name: "gassipass", managedObjectModel: Self.model)
        container.persistentStoreDescriptions = [privateStore, sharedStore]
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = loadError ?? error
        }
        if let loadError {
            throw loadError
        }
        let coordinator = container.persistentStoreCoordinator
        guard let privateURL = privateStore.url, let sharedURL = sharedStore.url,
              let openedPrivateStore = coordinator.persistentStore(for: privateURL),
              let openedSharedStore = coordinator.persistentStore(for: sharedURL)
        else {
            throw CocoaError(.persistentStoreOpen)
        }
        (self.privateStore, self.sharedStore) = (openedPrivateStore, openedSharedStore)
        // The view context shows the changes that CloudKit imports. A change
        // on this phone wins over an import of the same attribute.
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }
}

#if DEBUG
extension Stores {
    /// Writes every record type and field of the model into the development
    /// schema of the CloudKit container. CloudKit adds a field to that schema
    /// only when a record with a value for the field arrives, so a schema
    /// that grew from use lacks the fields that were always empty. Run it
    /// after each change of the model and before each deploy of the schema
    /// to production (README).
    ///
    /// It uses an empty store in a temporary folder, so the stores of the
    /// app stay as they are.
    static func initializeCloudKitSchema() throws {
        let folder = URL.temporaryDirectory.appending(path: "CloudKitSchema-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let description = NSPersistentStoreDescription(url: folder.appending(path: "schema.store"))
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudKitContainerIdentifier)
        let container = NSPersistentCloudKitContainer(name: "gassipass", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = loadError ?? error
        }
        if let loadError {
            throw loadError
        }
        try container.initializeCloudKitSchema()
    }
}
#endif
