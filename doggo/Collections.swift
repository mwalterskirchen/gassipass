//
//  Collections.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// The collections of all dogs and the areas and streets of the bundled map
/// packages, for every screen that shows them. `CollectionUpdates` keeps them current.
@Observable
final class Collections {
    /// The collection of each dog, empty until the first rebuild.
    private(set) var byDog: [PersistentIdentifier: DogCollection] = [:]
    /// The areas of all packages by BFS number, empty until they are loaded.
    private(set) var areas: [Int: Area] = [:]
    /// The streets of all packages by the BFS number of their area, empty
    /// until they are loaded.
    private(set) var streets: [Int: [Street]] = [:]
    /// The cantons of all packages, sorted, empty until the areas are loaded.
    private(set) var cantons: [String] = []

    /// The pages that the collection book has built, by canton, dog and
    /// records. A new load of the areas or a rebuild empties it.
    @ObservationIgnored private var pageCache: [PageKey: [CollectionBook.Page]] = [:]
    /// The canton where each dog has collected the most segments, for the
    /// collection book. A new load of the areas or a rebuild empties it.
    @ObservationIgnored private var cantonCache: [PersistentIdentifier?: String?] = [:]

    func collection(of dog: PersistentIdentifier?) -> DogCollection {
        dog.flatMap { byDog[$0] } ?? DogCollection()
    }

    /// Loads the areas and the streets off the main thread, from packages
    /// of its own, like the rebuild.
    func loadAreas() async {
        let (loadedAreas, loadedStreets, loadedCantons) = await Task.detached(priority: .userInitiated) {
            let packages = (try? MapPackage.bundled()) ?? []
            let areas = packages.flatMap { (try? $0.areas()) ?? [] }
            let streets = packages.flatMap { (try? $0.streets()) ?? [] }
            return (Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                    Dictionary(grouping: streets, by: \.id.area),
                    Set(areas.map(\.canton)).sorted())
        }.value
        guard !Task.isCancelled else { return }
        areas = loadedAreas
        streets = loadedStreets
        cantons = loadedCantons
        emptyCaches()
    }

    /// Rebuilds the collections of all dogs from all ended walks, off the
    /// main thread. The rebuild opens its own packages, because the map view
    /// reads the others on the main thread at the same time.
    func rebuild(dogs: [Dog], walks: [Walk]) async {
        let dogIDs = Set(dogs.map(\.persistentModelID))
        let walkData = walks.map { (dogs: Self.dogIDs(of: $0), trackData: $0.trackData) }
        let result = await Task.detached(priority: .userInitiated) { () -> [PersistentIdentifier: DogCollection]? in
            // A track that cannot be read collects nothing, as it shows as empty.
            let engineWalks = walkData.map { walk in
                CollectionEngine.Walk(
                    dogs: walk.dogs, track: (try? walk.trackData.map(Track.init(data:))) ?? Track())
            }
            guard let packages = try? MapPackage.bundled() else { return nil }
            // The packages are too big to load at once, so the engine gets
            // only the segments that the walks can cover.
            let boxes = engineWalks.flatMap { CollectionEngine.coverableBoxes(of: $0.track) }
            return CollectionEngine(segments: MapPackage.segments(in: boxes, of: packages))
                .rebuild(dogs: dogIDs, walks: engineWalks)
        }.value
        guard !Task.isCancelled, let result else { return }
        byDog = result
        emptyCaches()
    }

    private func emptyCaches() {
        pageCache = [:]
        cantonCache = [:]
    }

    /// Stores each record that the engine reports for a dog and an area or
    /// street that has no stored record yet.
    func recordCompleted(dogs: [Dog], in context: ModelContext) {
        guard !areas.isEmpty, !byDog.isEmpty else { return }
        func dog(_ id: PersistentIdentifier) -> Dog? {
            dogs.first { $0.persistentModelID == id }
        }

        let existingAreas = dogs.flatMap(\.completedAreaRecords)
        let areaRecords = CollectionEngine.completedRecords(
            collections: byDog, areas: Array(areas.values), existing: existingAreas)
        for record in areaRecords
        where CollectionEngine.completedDate(of: record.goal, for: record.dog, in: existingAreas) == nil {
            guard let dog = dog(record.dog) else { continue }
            context.insert(CompletedArea(dog: dog, area: record.goal, completedAt: record.date))
        }

        let existingStreets = dogs.flatMap(\.completedStreetRecords)
        let streetRecords = CollectionEngine.completedRecords(
            collections: byDog, streets: streets.values.flatMap { $0 }, existing: existingStreets)
        for record in streetRecords
        where CollectionEngine.completedDate(of: record.goal, for: record.dog, in: existingStreets) == nil {
            guard let dog = dog(record.dog) else { continue }
            context.insert(CompletedStreet(dog: dog, street: record.goal, completedAt: record.date))
        }
    }

    fileprivate static func dogIDs(of walk: Walk) -> Set<PersistentIdentifier> {
        Set((walk.dogs ?? []).map(\.persistentModelID))
    }
}

extension Collections {
    /// The pages of every area of the canton for the dog, for the collection
    /// book. The book shows many areas, so the pages are built only when the
    /// areas, the collections or the records of the dog change.
    func pages(canton: String, for dog: Dog) -> [CollectionBook.Page] {
        // These reads come first, so that the screen observes the areas, the
        // collection and the records also when the cache holds the pages.
        let areas = areas
        let collection = collection(of: dog.persistentModelID)
        let records = dog.completedAreaRecords
        let key = PageKey(canton: canton, dog: dog.persistentModelID, records: records)
        if let pages = pageCache[key] { return pages }
        let pages = CollectionBook.pages(
            canton: canton, areas: Array(areas.values), collection: collection,
            dog: dog.persistentModelID, records: records)
        pageCache[key] = pages
        return pages
    }

    /// The canton where the dog has collected the most segments, or nil if
    /// the dog has collected none.
    func cantonWithMostCollected(by dog: PersistentIdentifier?) -> String? {
        let areas = areas
        let collection = collection(of: dog)
        if let canton = cantonCache[dog] { return canton }
        var countByCanton: [String: Int] = [:]
        for segment in collection.collected.values {
            if let canton = areas[segment.area]?.canton {
                countByCanton[canton, default: 0] += 1
            }
        }
        let canton = countByCanton.isEmpty
            ? nil : cantons.max { (countByCanton[$0] ?? 0) < (countByCanton[$1] ?? 0) }
        cantonCache[dog] = canton
        return canton
    }

    /// The pages of the pinned areas for the dog, for the home screen.
    func pinnedPages(_ pinned: [Area.ID], for dog: Dog) -> [CollectionBook.Page] {
        CollectionBook.pinnedPages(
            pinned: pinned, areas: Array(areas.values), collection: collection(of: dog.persistentModelID),
            dog: dog.persistentModelID, records: dog.completedAreaRecords)
    }
}

extension Dog {
    /// The stored completed records of the areas of the dog. They come from
    /// the relationship, which changes at once when a record is inserted.
    var completedAreaRecords: [CompletedRecord<PersistentIdentifier, Area.ID>] {
        (completedAreas ?? []).map {
            CompletedRecord(dog: persistentModelID, goal: $0.area, date: $0.completedAt)
        }
    }

    /// The stored completed records of the streets of the dog.
    var completedStreetRecords: [CompletedRecord<PersistentIdentifier, Street.ID>] {
        (completedStreets ?? []).map {
            CompletedRecord(
                dog: persistentModelID, goal: Street.ID(area: $0.area, name: $0.street), date: $0.completedAt)
        }
    }
}

/// Keeps the collections current. It loads the areas and rebuilds the
/// collections at start and whenever the ended walks or their dogs change,
/// and then stores the new completed records.
struct CollectionUpdates: ViewModifier {
    @Environment(Collections.self) private var collections
    @Environment(\.modelContext) private var modelContext
    @Query private var dogs: [Dog]
    /// A walk counts when it has ended. During a walk, `LiveFeedback` matches its points.
    @Query(filter: #Predicate<Walk> { $0.endedAt != nil }) private var walks: [Walk]

    func body(content: Content) -> some View {
        content
            .task {
                await collections.loadAreas()
                collections.recordCompleted(dogs: dogs, in: modelContext)
            }
            .task(id: collectionInput) {
                await collections.rebuild(dogs: dogs, walks: walks)
                collections.recordCompleted(dogs: dogs, in: modelContext)
            }
    }

    /// What the collections depend on. A change starts a new rebuild.
    private var collectionInput: CollectionInput {
        CollectionInput(
            dogs: Set(dogs.map(\.persistentModelID)),
            walks: walks.map { WalkInput(walk: $0.persistentModelID, dogs: Collections.dogIDs(of: $0)) })
    }
}

private struct PageKey: Hashable {
    let canton: String
    let dog: PersistentIdentifier
    let records: [CompletedRecord<PersistentIdentifier, Area.ID>]
}

private struct CollectionInput: Equatable {
    let dogs: Set<PersistentIdentifier>
    let walks: [WalkInput]
}

private struct WalkInput: Equatable {
    let walk: PersistentIdentifier
    let dogs: Set<PersistentIdentifier>
}
