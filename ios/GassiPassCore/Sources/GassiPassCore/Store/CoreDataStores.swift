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
/// (`LocalStore.copyPrivateStore(from:into:at:deviceID:)`).
///
/// The private store held the packs of the person on the phone and the
/// pinned areas. The shared store held the packs that the person joined, and
/// it stays behind (ADR 0006), so the app opens only the private store. The
/// stores synced with iCloud, but the copy opens the private store without
/// sync.
public final class CoreDataStores {
    public let container: NSPersistentCloudKitContainer

    /// The bundle of this package, which holds the Core Data model.
    public static let bundle = Bundle.module

    /// The model, loaded once, because Core Data expects one model for each
    /// entity class in a process.
    public static let model: NSManagedObjectModel = {
        guard let url = bundle.url(forResource: "gassipass", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url)
        else {
            fatalError("The Core Data model is missing from the app")
        }
        return model
    }()

    /// The file of the private store in the folder.
    public static func privateStoreURL(in folder: URL) -> URL {
        folder.appending(path: "default.store")
    }

    /// Copies the files of the private store in the folder into another
    /// folder: the store, its log files and the folder of the data that Core
    /// Data keeps outside the store, for example long tracks.
    public static func copyPrivateStoreFiles(from folder: URL, to destination: URL) throws {
        let store = privateStoreURL(in: folder).lastPathComponent
        for name in [store, "\(store)-wal", "\(store)-shm", ".default_SUPPORT"] {
            let file = folder.appending(path: name)
            guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { continue }
            try FileManager.default.copyItem(at: file, to: destination.appending(path: name))
        }
    }

    /// The description of the private store in the folder.
    public static func privateStoreDescription(in folder: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: privateStoreURL(in: folder))
        // Core Data opens a store with a history read-only without it.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.cloudKitContainerOptions = nil
        return description
    }

    /// Opens the private store in the folder, or creates it.
    public init(folder: URL) throws {
        container = NSPersistentCloudKitContainer(name: "gassipass", managedObjectModel: Self.model)
        container.persistentStoreDescriptions = [Self.privateStoreDescription(in: folder)]
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = loadError ?? error
        }
        if let loadError {
            throw loadError
        }
    }
}

extension CoreDataStores {
    @objc(Pack)
    public final class Pack: NSManagedObject {
        @NSManaged public var name: String
        @NSManaged public var createdAt: Date
        @NSManaged public var randomID: String
        @NSManaged public var isShared: Bool
        @NSManaged public var dogs: Set<Dog>
    }

    @objc(Dog)
    public final class Dog: NSManagedObject {
        @NSManaged public var name: String
        @NSManaged public var photoData: Data?
        @NSManaged public var retiredAt: Date?
        @NSManaged public var retirementReason: String
        @NSManaged public var walks: Set<Walk>
        @NSManaged public var completedAreas: Set<CompletedArea>
        @NSManaged public var completedStreets: Set<CompletedStreet>
        @NSManaged public var pack: Pack?
    }

    @objc(Walk)
    public final class Walk: NSManagedObject {
        @NSManaged public var startedAt: Date
        @NSManaged public var endedAt: Date?
        @NSManaged public var trackData: Data?
        @NSManaged public var distanceMetres: Double
        @NSManaged public var distanceVersion: Int
        @NSManaged public var continuedAt: Date?
        @NSManaged public var deviceID: String
        @NSManaged public var memberName: String
        @NSManaged public var dogs: Set<Dog>
    }

    @objc(CompletedArea)
    public final class CompletedArea: NSManagedObject {
        @NSManaged public var dog: Dog?
        @NSManaged public var area: Int
        @NSManaged public var completedAt: Date
        /// A random ID, or empty in a record from before iCloud sync.
        @NSManaged public var randomID: String
    }

    @objc(CompletedStreet)
    public final class CompletedStreet: NSManagedObject {
        @NSManaged public var dog: Dog?
        @NSManaged public var area: Int
        @NSManaged public var street: String
        @NSManaged public var completedAt: Date
        /// A random ID, or empty in a record from before iCloud sync.
        @NSManaged public var randomID: String

        public var streetID: Street.ID {
            Street.ID(area: area, name: street)
        }
    }

    @objc(PinnedArea)
    public final class PinnedArea: NSManagedObject {
        @NSManaged public var area: Int
    }
}
