//
//  LocalStoreCopyTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 07.10.2026.
//

import CoreData
import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The copy of the Core Data stores into the SwiftData store (ADR 0006). The
/// test writes a private store and a shared store into a temporary folder,
/// copies them, and opens the copy again.
@MainActor
struct LocalStoreCopyTests {
    /// With a space, like "Application Support".
    let folder = URL.temporaryDirectory.appending(path: "LocalStoreCopyTests \(UUID().uuidString)")
    let started = Date(timeIntervalSinceReferenceDate: 812_000_000)
    let copiedAt = Date(timeIntervalSinceReferenceDate: 813_000_000)
    let packID = UUID()
    let completedAreaID = UUID()

    /// A track with enough points that it goes into a file outside the
    /// store, like the track of a long walk.
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

    /// A photo large enough that it goes into a file outside the store.
    let photo = Data(repeating: 0xAB, count: 300_000)
    let defaults = UserDefaults(suiteName: "LocalStoreCopyTests-\(UUID().uuidString)")!

    func otherDefaults() -> UserDefaults {
        UserDefaults(suiteName: "LocalStoreCopyTests-\(UUID().uuidString)")!
    }

    // MARK: The first launch

    @Test func theFirstLaunchCopiesTheOldStoreAndKeepsItsFiles() throws {
        try writeOldStores()

        let container = try LocalStore.open(in: folder, defaults: defaults, now: copiedAt)

        let dogs = try container.mainContext.fetch(Dog.all())
        #expect(dogs.map(\.name) == ["Bello", "Luna", "Max"])
        #expect(FileManager.default.fileExists(atPath: CoreDataStores.privateStoreURL(in: folder).path(percentEncoded: false)))
        #expect(try CoreDataStores(folder: folder).container.viewContext
            .count(for: NSFetchRequest<NSManagedObject>(entityName: "Dog")) == 4)
    }

    /// After a sign-out the store is empty, and the old store must not come back.
    @Test func aLaunchAfterTheCopyNeverCopiesAgainAlsoWhenTheStoreIsEmpty() throws {
        try writeOldStores()
        let first = try LocalStore.open(in: folder, defaults: defaults, now: copiedAt)
        try first.mainContext.delete(model: LocalSchemaV1.WalkDog.self)
        try first.mainContext.delete(model: Walk.self)
        try first.mainContext.delete(model: CompletedArea.self)
        try first.mainContext.delete(model: CompletedStreet.self)
        try first.mainContext.delete(model: Dog.self)
        try first.mainContext.delete(model: Pack.self)
        try first.mainContext.delete(model: PinnedArea.self)
        try first.mainContext.save()

        let next = try LocalStore.open(in: folder, defaults: defaults, now: copiedAt)

        #expect(try next.mainContext.fetchCount(FetchDescriptor<Dog>()) == 0)
        #expect(try next.mainContext.fetchCount(FetchDescriptor<PinnedArea>()) == 0)
    }

    /// The app can stop after the copy saved and before it noted that the
    /// copy is done.
    @Test func aCopyThatWasNotNotedAsDoneDoesNotCopyTwice() throws {
        try writeOldStores()
        _ = try LocalStore.open(in: folder, defaults: defaults, now: copiedAt)

        let next = try LocalStore.open(in: folder, defaults: otherDefaults(), now: copiedAt)

        #expect(try next.mainContext.fetchCount(FetchDescriptor<Dog>()) == 3)
        #expect(try next.mainContext.fetchCount(FetchDescriptor<Walk>()) == 2)
    }

    @Test func aPhoneWithoutAnOldStoreStartsEmptyAndCreatesNoOldStore() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let container = try LocalStore.open(in: folder, defaults: defaults, now: copiedAt)

        #expect(try container.mainContext.fetchCount(FetchDescriptor<Dog>()) == 0)
        #expect(!FileManager.default.fileExists(atPath: CoreDataStores.privateStoreURL(in: folder).path(percentEncoded: false)))
    }

    @Test func theChosenDogIsStillChosenAfterTheCopy() throws {
        let luna = try writeOldStores()
        defaults.set(luna, forKey: "chosenDogURI")

        let container = try LocalStore.open(in: folder, defaults: defaults, now: copiedAt)

        let dogs = try container.mainContext.fetch(Dog.all())
        #expect(DogChoice(defaults: defaults).shownDog(in: dogs)?.name == "Luna")
        #expect(defaults.object(forKey: "chosenDogURI") == nil)
    }

    // MARK: The copy

    @Test func theCopyKeepsEverythingOfThePrivateStore() throws {
        let copy = try copyStores()

        let packs = try copy.fetch(FetchDescriptor<LocalSchemaV1.Pack>())
        #expect(packs.count == 1)
        let pack = try #require(packs.first)
        #expect(pack.id == packID)
        #expect(pack.name == "Walterskirchen")
        #expect(pack.createdAt == started.addingTimeInterval(-86_400))

        let dogs = try copy.fetch(FetchDescriptor<LocalSchemaV1.Dog>(sortBy: [SortDescriptor(\.name)]))
        #expect(dogs.map(\.name) == ["Bello", "Luna", "Max"])
        let (bello, luna, max) = (dogs[0], dogs[1], dogs[2])
        #expect(bello.photoData == photo)
        #expect(bello.retiredAt == nil)
        #expect(bello.pack === pack)
        #expect(luna.retiredAt == started.addingTimeInterval(86_400))
        #expect(luna.retirementReason == "Old age")
        #expect(luna.pack === pack)
        #expect(max.pack == nil)
        #expect(pack.dogs?.map(\.name).sorted() == ["Bello", "Luna"])

        let walks = try copy.fetch(FetchDescriptor<LocalSchemaV1.Walk>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(walks.count == 2)
        let (long, short) = (walks[0], walks[1])
        #expect(long.startedAt == started)
        #expect(long.endedAt == started.addingTimeInterval(5_000))
        #expect(try Track(data: try #require(long.trackData)) == longTrack)
        #expect(long.distanceMetres == 5_559.5)
        #expect(long.distanceVersion == 2)
        #expect(long.continuedAt == started.addingTimeInterval(3_600))
        #expect(long.deviceID == "phone")
        #expect(long.memberName == "Anna")
        #expect(long.sortedDogNames == ["Bello", "Luna"])
        #expect(short.endedAt == nil)
        #expect(try Track(data: try #require(short.trackData)) == shortTrack)
        #expect(short.deviceID == "")
        #expect(short.memberName == "")
        #expect(short.sortedDogNames == ["Bello"])
        #expect(bello.walkDogs?.count == 2)
        #expect(luna.walkDogs?.count == 1)
        #expect(max.walkDogs?.isEmpty == true)

        let areas = try copy.fetch(FetchDescriptor<LocalSchemaV1.CompletedArea>(sortBy: [SortDescriptor(\.area)]))
        #expect(areas.map(\.area) == [243, 247])
        #expect(areas.first?.completedAt == started.addingTimeInterval(5_000))
        #expect(areas.first?.dog === bello)
        #expect(areas.last?.dog === luna)
        // The two records had the same random ID. One of them keeps it.
        #expect(Set(areas.map(\.id)).count == 2)
        #expect(areas.contains { $0.id == completedAreaID })

        let streets = try copy.fetch(FetchDescriptor<LocalSchemaV1.CompletedStreet>(sortBy: [SortDescriptor(\.street)]))
        #expect(streets.map(\.street) == ["Kirchstrasse", "Zürcherstrasse"])
        #expect(streets.first?.dog == nil)
        #expect(streets.last?.area == 243)
        #expect(streets.last?.completedAt == started.addingTimeInterval(4_000))
        #expect(streets.last?.dog === luna)

        // Two phones could pin the same area on iCloud. On the phone it is one pin.
        let pins = try copy.fetch(FetchDescriptor<LocalSchemaV1.PinnedArea>())
        #expect(pins.map(\.area).sorted() == [243, 247])
    }

    @Test func theCopyHasNothingOfTheSharedStore() throws {
        let copy = try copyStores()

        let packs = try copy.fetch(FetchDescriptor<LocalSchemaV1.Pack>()).map(\.name)
        let dogs = try copy.fetch(FetchDescriptor<LocalSchemaV1.Dog>()).map(\.name)
        let walks = try copy.fetch(FetchDescriptor<LocalSchemaV1.Walk>())
        let areas = try copy.fetch(FetchDescriptor<LocalSchemaV1.CompletedArea>()).map(\.area)
        let streets = try copy.fetch(FetchDescriptor<LocalSchemaV1.CompletedStreet>()).map(\.street)
        let pins = try copy.fetch(FetchDescriptor<LocalSchemaV1.PinnedArea>()).map(\.area)

        #expect(!packs.contains("Neighbours"))
        #expect(!dogs.contains("Rex"))
        #expect(!walks.contains { $0.memberName == "Nina" })
        #expect(!areas.contains(250))
        #expect(!streets.contains("Bahnhofstrasse"))
        #expect(!pins.contains(999))
    }

    @Test func everyCopiedRowWaitsToUpload() throws {
        let copy = try copyStores()

        var rows: [any UploadingRow] = []
        rows += try copy.fetch(FetchDescriptor<LocalSchemaV1.Pack>())
        rows += try copy.fetch(FetchDescriptor<LocalSchemaV1.Dog>())
        rows += try copy.fetch(FetchDescriptor<LocalSchemaV1.Walk>())
        rows += try copy.fetch(FetchDescriptor<LocalSchemaV1.WalkDog>())
        rows += try copy.fetch(FetchDescriptor<LocalSchemaV1.CompletedArea>())
        rows += try copy.fetch(FetchDescriptor<LocalSchemaV1.CompletedStreet>())

        #expect(rows.count == 13)
        #expect(rows.allSatisfy { $0.isWaitingToUpload })
        #expect(rows.allSatisfy { $0.changedAt == copiedAt })
        #expect(rows.allSatisfy { $0.deletedAt == nil })
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    /// Writes the Core Data stores into the folder of the test, and returns
    /// the URI of the object ID of Luna.
    @discardableResult
    private func writeOldStores() throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try writeCoreDataStores(CoreDataStores(folder: folder))
    }

    /// Writes the Core Data stores into the folder, opens them again, copies
    /// them into a SwiftData store in the same folder, and returns a new
    /// context on the copy, which sees only what the copy saved.
    private func copyStores() throws -> ModelContext {
        try writeOldStores()
        let stores = try CoreDataStores(folder: folder)

        let copyURL = folder.appending(path: "copy.store")
        try LocalStore.copyPrivateStore(
            from: stores, into: ModelContext(try LocalStore.container(at: copyURL)), at: copiedAt)

        return ModelContext(try LocalStore.container(at: copyURL))
    }

    /// Writes the stores, and returns the URI of the object ID of Luna, which
    /// the choice of the dog stored.
    @discardableResult
    private func writeCoreDataStores(_ stores: CoreDataStores) throws -> URL {
        let context = stores.container.viewContext

        let pack = CoreDataStores.Pack(context: context)
        pack.name = "Walterskirchen"
        pack.createdAt = started.addingTimeInterval(-86_400)
        pack.randomID = packID.uuidString
        pack.isShared = true

        let bello = CoreDataStores.Dog(name: "Bello", context: context)
        bello.photoData = photo
        bello.pack = pack
        let luna = CoreDataStores.Dog(name: "Luna", context: context)
        luna.retiredAt = started.addingTimeInterval(86_400)
        luna.retirementReason = "Old age"
        luna.pack = pack
        // A dog from before the packs, which has no pack yet.
        let max = CoreDataStores.Dog(name: "Max", context: context)

        let long = CoreDataStores.Walk(startedAt: started, dogs: [bello, luna], context: context)
        long.endedAt = started.addingTimeInterval(5_000)
        long.trackData = longTrack.data
        long.distanceMetres = 5_559.5
        long.distanceVersion = 2
        long.continuedAt = started.addingTimeInterval(3_600)
        long.deviceID = "phone"
        long.memberName = "Anna"
        let short = CoreDataStores.Walk(startedAt: started.addingTimeInterval(10_000), dogs: [bello], context: context)
        short.trackData = shortTrack.data

        let area = CoreDataStores.CompletedArea(dog: bello, area: 243, completedAt: started.addingTimeInterval(5_000), context: context)
        area.randomID = completedAreaID.uuidString
        // A record from before iCloud sync has an empty random ID.
        let street = CoreDataStores.CompletedStreet(
            dog: luna, street: Street.ID(area: 243, name: "Zürcherstrasse"),
            completedAt: started.addingTimeInterval(4_000), context: context)
        street.randomID = ""
        // A second record with the same random ID, which iCloud could make.
        let sameID = CoreDataStores.CompletedArea(dog: luna, area: 247, completedAt: started, context: context)
        sameID.randomID = completedAreaID.uuidString
        // A record whose dog never arrived from iCloud.
        let withoutDog = CoreDataStores.CompletedStreet(
            dog: bello, street: Street.ID(area: 243, name: "Kirchstrasse"), completedAt: started, context: context)
        withoutDog.dog = nil

        let pins = [243, 247, 243].map { CoreDataStores.PinnedArea(area: $0, context: context) }

        let records = [area, street, sameID, withoutDog]
        for object in [pack, bello, luna, max, long, short] + records + pins as [NSManagedObject] {
            context.assign(object, to: stores.privateStore)
        }

        // A pack that this person joined, which the copy leaves out.
        let sharedPack = CoreDataStores.Pack(context: context)
        sharedPack.name = "Neighbours"
        sharedPack.randomID = UUID().uuidString
        let rex = CoreDataStores.Dog(name: "Rex", context: context)
        rex.pack = sharedPack
        let sharedWalk = CoreDataStores.Walk(startedAt: started, dogs: [rex], context: context)
        sharedWalk.trackData = shortTrack.data
        sharedWalk.memberName = "Nina"
        let sharedArea = CoreDataStores.CompletedArea(dog: rex, area: 250, completedAt: started, context: context)
        let sharedStreet = CoreDataStores.CompletedStreet(
            dog: rex, street: Street.ID(area: 247, name: "Bahnhofstrasse"), completedAt: started, context: context)
        let sharedPin = CoreDataStores.PinnedArea(area: 999, context: context)
        for object in [sharedPack, rex, sharedWalk, sharedArea, sharedStreet, sharedPin] as [NSManagedObject] {
            context.assign(object, to: stores.sharedStore)
        }

        try context.save()
        return luna.objectID.uriRepresentation()
    }
}

private extension LocalSchemaV1.Walk {
    /// The sorted names of the dogs of the walk.
    var sortedDogNames: [String] {
        (walkDogs ?? []).compactMap { $0.dog?.name }.sorted()
    }
}
