//
//  Collections.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// The collections of all dogs and the areas of the bundled map packages,
/// for every screen that shows them. `CollectionUpdates` keeps them current.
@Observable
final class Collections {
    /// The collection of each dog, empty until the first rebuild.
    private(set) var byDog: [PersistentIdentifier: DogCollection] = [:]
    /// The areas of all packages by BFS number, empty until they are loaded.
    private(set) var areas: [Int: Area] = [:]

    func collection(of dog: PersistentIdentifier?) -> DogCollection {
        dog.flatMap { byDog[$0] } ?? DogCollection()
    }

    /// Loads the areas off the main thread, from packages of its own, like
    /// the rebuild.
    func loadAreas() async {
        let loaded = await Task.detached(priority: .userInitiated) { () -> [Int: Area] in
            let packages = (try? MapPackage.bundled()) ?? []
            let areas = packages.flatMap { (try? $0.areas()) ?? [] }
            return Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }.value
        guard !Task.isCancelled else { return }
        areas = loaded
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
            var segments: [Segment.ID: Segment] = [:]
            for box in engineWalks.flatMap({ CollectionEngine.coverableBoxes(of: $0.track) }) {
                for package in packages {
                    for segment in (try? package.segments(in: box)) ?? [] {
                        segments[segment.id] = segment
                    }
                }
            }
            return CollectionEngine(segments: Array(segments.values)).rebuild(dogs: dogIDs, walks: engineWalks)
        }.value
        guard !Task.isCancelled, let result else { return }
        byDog = result
    }

    /// Stores each record that the engine reports for a dog and area that
    /// has no stored record yet.
    func recordCompletedAreas(dogs: [Dog], in context: ModelContext) {
        guard !areas.isEmpty, !byDog.isEmpty else { return }
        let existing = dogs.flatMap(\.completedRecords)
        let records = CollectionEngine.completedRecords(
            collections: byDog, areas: Array(areas.values), existing: existing)
        for record in records
        where CollectionEngine.completedDate(of: record.area, for: record.dog, in: existing) == nil {
            guard let dog = dogs.first(where: { $0.persistentModelID == record.dog }) else { continue }
            context.insert(CompletedArea(dog: dog, area: record.area, completedAt: record.date))
        }
    }

    fileprivate static func dogIDs(of walk: Walk) -> Set<PersistentIdentifier> {
        Set((walk.dogs ?? []).map(\.persistentModelID))
    }
}

extension Dog {
    /// The stored completed records of the dog. They come from the
    /// relationship, which changes at once when a record is inserted.
    var completedRecords: [CompletedRecord<PersistentIdentifier>] {
        (completedAreas ?? []).map {
            CompletedRecord(dog: persistentModelID, area: $0.area, date: $0.completedAt)
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
    /// A walk counts when it has ended. Live matching during a walk comes later.
    @Query(filter: #Predicate<Walk> { $0.endedAt != nil }) private var walks: [Walk]

    func body(content: Content) -> some View {
        content
            .task {
                await collections.loadAreas()
                collections.recordCompletedAreas(dogs: dogs, in: modelContext)
            }
            .task(id: collectionInput) {
                await collections.rebuild(dogs: dogs, walks: walks)
                collections.recordCompletedAreas(dogs: dogs, in: modelContext)
            }
    }

    /// What the collections depend on. A change starts a new rebuild.
    private var collectionInput: CollectionInput {
        CollectionInput(
            dogs: Set(dogs.map(\.persistentModelID)),
            walks: walks.map { WalkInput(walk: $0.persistentModelID, dogs: Collections.dogIDs(of: $0)) })
    }
}

private struct CollectionInput: Equatable {
    let dogs: Set<PersistentIdentifier>
    let walks: [WalkInput]
}

private struct WalkInput: Equatable {
    let walk: PersistentIdentifier
    let dogs: Set<PersistentIdentifier>
}
