//
//  CoreDataStores.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import CoreData

/// The Core Data stores of the builds before ADR 0006, with the classes of
/// their model. The app opens them only once, at the first launch of a build
/// with SwiftData, and copies the private store into the local store
/// (`LocalStore.copyPrivateStore(from:into:at:)`).
///
/// The private store held the packs of the person on the phone and the
/// pinned areas. The shared store held the packs that the person joined. The
/// stores synced with iCloud, but the copy opens them without sync.
final class CoreDataStores {
    let container: NSPersistentCloudKitContainer
    let privateStore: NSPersistentStore
    let sharedStore: NSPersistentStore

    /// The model, loaded once, because Core Data expects one model for each
    /// entity class in a process.
    static let model: NSManagedObjectModel = {
        guard let url = Bundle(for: CoreDataStores.self).url(forResource: "gassipass", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url)
        else {
            fatalError("The Core Data model is missing from the app")
        }
        return model
    }()

    /// The file of the private store in the folder.
    static func privateStoreURL(in folder: URL) -> URL {
        folder.appending(path: "default.store")
    }

    /// Copies the files of the private store in the folder into another
    /// folder: the store, its log files and the folder of the data that Core
    /// Data keeps outside the store, for example long tracks.
    static func copyPrivateStoreFiles(from folder: URL, to destination: URL) throws {
        let store = privateStoreURL(in: folder).lastPathComponent
        for name in [store, "\(store)-wal", "\(store)-shm", ".default_SUPPORT"] {
            let file = folder.appending(path: name)
            guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { continue }
            try FileManager.default.copyItem(at: file, to: destination.appending(path: name))
        }
    }

    private static func sharedStoreURL(in folder: URL) -> URL {
        folder.appending(path: "shared.store")
    }

    /// Opens the stores in the folder, or creates them.
    init(folder: URL) throws {
        let descriptions = [Self.privateStoreURL(in: folder), Self.sharedStoreURL(in: folder)].map { url in
            let description = NSPersistentStoreDescription(url: url)
            // Core Data opens a store with a history read-only without it.
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.cloudKitContainerOptions = nil
            return description
        }
        container = NSPersistentCloudKitContainer(name: "gassipass", managedObjectModel: Self.model)
        container.persistentStoreDescriptions = descriptions
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = loadError ?? error
        }
        if let loadError {
            throw loadError
        }
        let coordinator = container.persistentStoreCoordinator
        guard let openedPrivateStore = descriptions[0].url.flatMap(coordinator.persistentStore(for:)),
              let openedSharedStore = descriptions[1].url.flatMap(coordinator.persistentStore(for:))
        else {
            throw CocoaError(.persistentStoreOpen)
        }
        (privateStore, sharedStore) = (openedPrivateStore, openedSharedStore)
    }
}

extension CoreDataStores {
    @objc(Pack)
    final class Pack: NSManagedObject {
        @NSManaged var name: String
        @NSManaged var createdAt: Date
        @NSManaged var randomID: String
        @NSManaged var isShared: Bool
        @NSManaged var dogs: Set<Dog>
    }

    @objc(Dog)
    final class Dog: NSManagedObject {
        @NSManaged var name: String
        @NSManaged var photoData: Data?
        @NSManaged var retiredAt: Date?
        @NSManaged var retirementReason: String
        @NSManaged var walks: Set<Walk>
        @NSManaged var completedAreas: Set<CompletedArea>
        @NSManaged var completedStreets: Set<CompletedStreet>
        @NSManaged var pack: Pack?

        convenience init(name: String, context: NSManagedObjectContext) {
            self.init(context: context)
            self.name = name
        }
    }

    @objc(Walk)
    final class Walk: NSManagedObject {
        @NSManaged var startedAt: Date
        @NSManaged var endedAt: Date?
        @NSManaged var trackData: Data?
        @NSManaged var distanceMetres: Double
        @NSManaged var distanceVersion: Int
        @NSManaged var continuedAt: Date?
        @NSManaged var deviceID: String
        @NSManaged var memberName: String
        @NSManaged var dogs: Set<Dog>

        convenience init(startedAt: Date, dogs: some Sequence<Dog>, context: NSManagedObjectContext) {
            self.init(context: context)
            self.startedAt = startedAt
            self.dogs = Set(dogs)
        }
    }

    @objc(CompletedArea)
    final class CompletedArea: NSManagedObject {
        @NSManaged var dog: Dog?
        @NSManaged var area: Int
        @NSManaged var completedAt: Date
        /// A random ID, or empty in a record from before iCloud sync.
        @NSManaged var randomID: String

        convenience init(dog: Dog, area: Int, completedAt: Date, context: NSManagedObjectContext) {
            self.init(context: context)
            self.dog = dog
            self.area = area
            self.completedAt = completedAt
            randomID = UUID().uuidString
        }
    }

    @objc(CompletedStreet)
    final class CompletedStreet: NSManagedObject {
        @NSManaged var dog: Dog?
        @NSManaged var area: Int
        @NSManaged var street: String
        @NSManaged var completedAt: Date
        /// A random ID, or empty in a record from before iCloud sync.
        @NSManaged var randomID: String

        convenience init(dog: Dog, street: Street.ID, completedAt: Date, context: NSManagedObjectContext) {
            self.init(context: context)
            self.dog = dog
            self.area = street.area
            self.street = street.name
            self.completedAt = completedAt
            randomID = UUID().uuidString
        }

        var streetID: Street.ID {
            Street.ID(area: area, name: street)
        }
    }

    @objc(PinnedArea)
    final class PinnedArea: NSManagedObject {
        @NSManaged var area: Int

        convenience init(area: Int, context: NSManagedObjectContext) {
            self.init(context: context)
            self.area = area
        }
    }
}
