//
//  StoreMigrationTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import CoreData
import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The move from SwiftData to Core Data (ADR 0004). The test writes a store
/// file with the SwiftData schema that the phones have today, and opens it
/// with the Core Data stack.
@MainActor
struct StoreMigrationTests {
    let folder = URL.temporaryDirectory.appending(path: "StoreMigrationTests-\(UUID().uuidString)")
    let started = Date(timeIntervalSinceReferenceDate: 812_000_000)

    /// A track with enough points that SwiftData keeps it in a file outside
    /// the store, like the track of a long walk.
    var longTrack: Track {
        Track(points: (0..<5_000).map { index in
            TrackPoint(
                latitude: 47.4 + Double(index) * 0.000_01, longitude: 8.4,
                timestamp: started.addingTimeInterval(Double(index)), horizontalAccuracy: 5)
        })
    }

    var shortTrack: Track {
        Track(points: [
            TrackPoint(latitude: 47.40, longitude: 8.40, timestamp: started, horizontalAccuracy: 8),
            TrackPoint(latitude: 47.41, longitude: 8.40, timestamp: started.addingTimeInterval(60), horizontalAccuracy: 4),
        ])
    }

    /// A photo large enough that SwiftData keeps it in a file outside the store.
    let photo = Data(repeating: 0xAB, count: 300_000)

    @Test func coreDataFindsEverythingThatSwiftDataStored() throws {
        try writeSwiftDataStore()

        let stores = try Stores(folder: folder, syncsWithCloudKit: false)
        let context = stores.container.viewContext

        let dogs = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Dog"))
            .sorted { $0.string("name") < $1.string("name") }
        #expect(dogs.map { $0.string("name") } == ["Bello", "Luna"])
        let (bello, luna) = (dogs[0], dogs[1])
        #expect(bello.value(forKey: "photoData") as? Data == photo)
        #expect(bello.value(forKey: "retiredAt") == nil)
        #expect(luna.value(forKey: "retiredAt") as? Date == started.addingTimeInterval(86_400))
        #expect(luna.string("retirementReason") == "Old age")

        let walks = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Walk"))
            .sorted { $0.date("startedAt") < $1.date("startedAt") }
        #expect(walks.count == 2)
        let (long, short) = (walks[0], walks[1])
        #expect(long.date("startedAt") == started)
        #expect(long.value(forKey: "endedAt") as? Date == started.addingTimeInterval(5_000))
        #expect(try Track(data: try #require(long.value(forKey: "trackData") as? Data)) == longTrack)
        #expect(long.value(forKey: "distanceMetres") as? Double == 5_559.5)
        #expect(long.value(forKey: "distanceVersion") as? Int == 2)
        #expect(long.value(forKey: "continuedAt") as? Date == started.addingTimeInterval(3_600))
        #expect(long.string("deviceID") == "phone")
        #expect(long.names(of: "dogs") == ["Bello", "Luna"])
        #expect(short.value(forKey: "endedAt") == nil)
        #expect(try Track(data: try #require(short.value(forKey: "trackData") as? Data)) == shortTrack)
        #expect(short.string("deviceID") == "")
        #expect(short.names(of: "dogs") == ["Bello"])
        #expect(bello.set(of: "walks").count == 2)
        #expect(luna.set(of: "walks").count == 1)

        let areas = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "CompletedArea"))
        #expect(areas.count == 1)
        #expect(areas.first?.value(forKey: "area") as? Int == 243)
        #expect(areas.first?.value(forKey: "completedAt") as? Date == started.addingTimeInterval(5_000))
        #expect(areas.first?.string("randomID") == "A")
        #expect(areas.first?.value(forKey: "dog") as? NSManagedObject == bello)

        let streets = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "CompletedStreet"))
        #expect(streets.count == 1)
        #expect(streets.first?.value(forKey: "area") as? Int == 243)
        #expect(streets.first?.string("street") == "Zürcherstrasse")
        #expect(streets.first?.value(forKey: "completedAt") as? Date == started.addingTimeInterval(4_000))
        #expect(streets.first?.string("randomID") == "")
        #expect(streets.first?.value(forKey: "dog") as? NSManagedObject == luna)

        let pins = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "PinnedArea"))
        #expect(Set(pins.compactMap { $0.value(forKey: "area") as? Int }) == [243, 247])

        #expect(Set(dogs.compactMap(\.objectID.persistentStore)) == [stores.privateStore])
    }

    /// The model matches the schema exactly, so that Core Data opens the
    /// store file without a migration. Core Data would also migrate a store
    /// with a different schema, from the copy of the old model in the file.
    @Test func theModelMatchesTheSwiftDataSchema() throws {
        try writeSwiftDataStore()

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite, at: Stores.privateStoreURL(in: folder))

        #expect(Stores.model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata))
    }

    /// Writes the store file of the app with SwiftData into the folder.
    /// The container closes the file when it goes away at the end.
    private func writeSwiftDataStore() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let container = try ModelContainer(
            for: Schema(versionedSchema: SwiftDataSchema.self),
            configurations: ModelConfiguration(url: Stores.privateStoreURL(in: folder), cloudKitDatabase: .none))
        let context = ModelContext(container)

        let bello = SwiftDataSchema.Dog()
        bello.name = "Bello"
        bello.photoData = photo
        let luna = SwiftDataSchema.Dog()
        luna.name = "Luna"
        luna.retiredAt = started.addingTimeInterval(86_400)
        luna.retirementReason = "Old age"

        let long = SwiftDataSchema.Walk()
        long.startedAt = started
        long.endedAt = started.addingTimeInterval(5_000)
        long.trackData = longTrack.data
        long.distanceMetres = 5_559.5
        long.distanceVersion = 2
        long.continuedAt = started.addingTimeInterval(3_600)
        long.deviceID = "phone"
        long.dogs = [bello, luna]
        let short = SwiftDataSchema.Walk()
        short.startedAt = started.addingTimeInterval(10_000)
        short.trackData = shortTrack.data
        short.dogs = [bello]

        let area = SwiftDataSchema.CompletedArea()
        area.dog = bello
        area.area = 243
        area.completedAt = started.addingTimeInterval(5_000)
        area.randomID = "A"
        let street = SwiftDataSchema.CompletedStreet()
        street.dog = luna
        street.area = 243
        street.street = "Zürcherstrasse"
        street.completedAt = started.addingTimeInterval(4_000)

        for model in [bello, luna, long, short, area, street] as [any PersistentModel] {
            context.insert(model)
        }
        context.insert(SwiftDataSchema.PinnedArea(area: 243))
        context.insert(SwiftDataSchema.PinnedArea(area: 247))
        try context.save()
    }
}

/// The SwiftData schema of the store on the phones before the move to Core
/// Data. It is a copy of the attributes and relationships of the SwiftData
/// models, so that the test keeps the old schema after the models go away.
enum SwiftDataSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Dog.self, Walk.self, CompletedArea.self, CompletedStreet.self, PinnedArea.self]
    }

    @Model
    final class Dog {
        var name: String = ""
        @Attribute(.externalStorage)
        var photoData: Data?
        var retiredAt: Date?
        var retirementReason: String = ""
        @Relationship(inverse: \Walk.dogs)
        var walks: [Walk]? = []
        @Relationship(inverse: \CompletedArea.dog)
        var completedAreas: [CompletedArea]? = []
        @Relationship(inverse: \CompletedStreet.dog)
        var completedStreets: [CompletedStreet]? = []

        init() {}
    }

    @Model
    final class Walk {
        var startedAt: Date = Date.now
        var endedAt: Date?
        @Attribute(.externalStorage)
        var trackData: Data?
        var distanceMetres: Double = 0
        var distanceVersion: Int = 0
        var continuedAt: Date?
        var deviceID: String = ""
        var dogs: [Dog]? = []

        init() {}
    }

    @Model
    final class CompletedArea {
        var dog: Dog?
        var area: Int = 0
        var completedAt: Date = Date.now
        var randomID: String = ""

        init() {}
    }

    @Model
    final class CompletedStreet {
        var dog: Dog?
        var area: Int = 0
        var street: String = ""
        var completedAt: Date = Date.now
        var randomID: String = ""

        init() {}
    }

    @Model
    final class PinnedArea {
        var area: Int = 0

        init(area: Int) {
            self.area = area
        }
    }
}

private extension NSManagedObject {
    func string(_ key: String) -> String {
        value(forKey: key) as? String ?? "<missing>"
    }

    func date(_ key: String) -> Date {
        value(forKey: key) as? Date ?? .distantPast
    }

    func set(of key: String) -> Set<NSManagedObject> {
        value(forKey: key) as? Set<NSManagedObject> ?? []
    }

    /// The sorted names of the dogs in a to-many relationship.
    func names(of key: String) -> [String] {
        set(of: key).map { $0.string("name") }.sorted()
    }
}
