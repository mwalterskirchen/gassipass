//
//  LocalStore.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 07.10.2026.
//

import Foundation
import OSLog
import SwiftData

/// The SwiftData store on the phone (ADR 0006), with the models of
/// `LocalSchemaV1`. It never syncs with iCloud: the rows upload to the
/// server on their own.
enum LocalStore {
    static let schema = Schema(versionedSchema: LocalSchemaV1.self)

    /// The key in the user defaults that notes that the first launch has
    /// copied the Core Data store.
    private static let copiedKey = "copiedCoreDataStore"

    private static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "LocalStore")

    /// Opens the store in the file, or creates it.
    static func container(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
    }

    /// An empty store in memory, for the tests, the demo data and previews.
    static func inMemory() throws -> ModelContainer {
        try ModelContainer(
            for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    /// The store of the app in Application Support.
    static func app() throws -> ModelContainer {
        // A new install has no Application Support folder yet.
        try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        return try open(in: .applicationSupportDirectory, defaults: .standard, now: .now)
    }

    /// Opens the store in the folder, or creates it. The first launch copies
    /// the private Core Data store of the builds before ADR 0006 from the
    /// same folder, if there is one, and carries the choice of the dog over.
    /// The old files stay as they are. A copy that fails is logged, and the
    /// next launch tries again while the store is empty.
    static func open(in folder: URL, defaults: UserDefaults, now: Date) throws -> ModelContainer {
        let container = try container(at: folder.appending(path: "local.store"))
        guard !defaults.bool(forKey: copiedKey) else { return container }
        do {
            try copyOldStore(in: folder, into: container, defaults: defaults, now: now)
            defaults.set(true, forKey: copiedKey)
        } catch {
            logger.error("The Core Data store cannot be copied: \(String(describing: error), privacy: .public)")
        }
        return container
    }

    private static func copyOldStore(
        in folder: URL, into container: ModelContainer, defaults: UserDefaults, now: Date
    ) throws {
        let oldStore = CoreDataStores.privateStoreURL(in: folder)
        guard FileManager.default.fileExists(atPath: oldStore.path(percentEncoded: false)) else { return }
        let context = ModelContext(container)
        // The app can stop after the copy saved and before it noted the copy.
        guard try isEmpty(context) else { return }
        // Core Data migrates a store with an older model in place. The old
        // files are the backup in case the copy fails, so the copy reads a
        // copy of them.
        let snapshot = URL.temporaryDirectory.appending(path: "CoreDataStores-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: snapshot)
        }
        try CoreDataStores.copyPrivateStoreFiles(from: folder, to: snapshot)
        let dogIDs = try copyPrivateStore(from: CoreDataStores(folder: snapshot), into: context, at: now)
        DogChoice.carryOver(dogIDs: dogIDs, in: defaults)
    }

    private static func isEmpty(_ context: ModelContext) throws -> Bool {
        try context.fetchCount(FetchDescriptor<Pack>()) == 0
            && context.fetchCount(FetchDescriptor<Dog>()) == 0
            && context.fetchCount(FetchDescriptor<Walk>()) == 0
            && context.fetchCount(FetchDescriptor<PinnedArea>()) == 0
    }
}
