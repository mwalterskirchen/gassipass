//
//  Collections.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import OSLog
import SwiftData
import SwiftUI

/// The collections of all dogs and the areas and streets of the map
/// packages, for every screen that shows them.
///
/// `update()` brings them up to date with the store. It loads the areas and
/// the streets, rebuilds the collection of each dog from all its ended walks
/// (ADR 0002), and stores each new completed record. The app calls it at
/// launch, also when Core Location launches the app in the background during
/// a walk, and `CollectionUpdates` calls it whenever the ended walks or their
/// dogs change.
@Observable
final class Collections {
    /// The collection of each dog, empty until the first update.
    private(set) var byDog: [PersistentIdentifier: DogCollection] = [:]
    /// The areas of all packages by BFS number, empty until they are loaded.
    private(set) var areas: [Int: Area] = [:]
    /// The streets of all packages by the BFS number of their area, empty
    /// until they are loaded.
    private(set) var streets: [Int: [Street]] = [:]
    /// The cantons of all packages, sorted, empty until the areas are loaded.
    private(set) var cantons: [String] = []

    /// The pages that the collection book has built, by canton, dog and
    /// records. A new load of the areas or a new collection empties it.
    @ObservationIgnored private var pageCache: [PageKey: [CollectionBook.Page]] = [:]
    /// The canton where each dog has collected the most segments, for the
    /// collection book. A new load of the areas or a new collection empties it.
    @ObservationIgnored private var cantonCache: [PersistentIdentifier?: String?] = [:]

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let matcher: Matcher
    @ObservationIgnored private var areasAreLoaded = false
    /// The update that runs now. A new update cancels it.
    @ObservationIgnored private var running: Task<Void, Never>?

    private static let logger = Logger(subsystem: "ch.mwalterskirchen.doggo", category: "Collections")

    /// - Parameters:
    ///   - context: The store of the dogs, the walks and the completed records.
    ///   - packageURLs: The files of the map packages.
    ///   - cacheRoot: The folder for the stored matches of the walks, or nil
    ///     to store none.
    init(context: ModelContext, packageURLs: [URL], cacheRoot: URL?) {
        self.context = context
        matcher = Matcher(packageURLs: packageURLs, cacheRoot: cacheRoot)
    }

    func collection(of dog: PersistentIdentifier?) -> DogCollection {
        dog.flatMap { byDog[$0] } ?? DogCollection()
    }

    /// Brings the areas, the collections and the completed records up to
    /// date with the store.
    ///
    /// A newer update cancels this one, which then changes nothing more. An
    /// update that cannot read a map package keeps the previous collections
    /// and stores nothing, and the next update tries again.
    func update() async {
        running?.cancel()
        let update = Task { await run() }
        running = update
        await update.value
    }

    private func run() async {
        do {
            try await runSteps()
        } catch is CancellationError {
            // A newer update does the work.
        } catch {
            Self.logger.error("The collections cannot update: \(String(describing: error), privacy: .public)")
        }
    }

    private func runSteps() async throws {
        let dogs = try context.fetch(FetchDescriptor<Dog>())
        let walks = try context.fetch(FetchDescriptor(predicate: #Predicate<Walk> { $0.endedAt != nil }))
        let endedWalks = walks.compactMap { walk in
            WalkMatchCache.Key(walk).map { Matcher.EndedWalk(key: $0, dogs: Self.dogIDs(of: walk)) }
        }

        let stored = try await matcher.stored(for: endedWalks.map(\.key), loadsAreas: !areasAreLoaded)
        try Task.checkCancellation()
        if let loaded = stored.loadedAreas {
            areas = loaded.areas
            streets = loaded.streets
            cantons = loaded.cantons
            areasAreLoaded = true
            emptyCaches()
        }

        // Only the walks without a stored match read their track, which is
        // stored outside the database.
        var trackData: [WalkMatchCache.Key: Data?] = [:]
        for walk in walks {
            if let key = WalkMatchCache.Key(walk), stored.matches[key] == nil {
                // Also a walk with no track data yet gets an entry, so that
                // it collects nothing until its track arrives.
                trackData.updateValue(walk.trackData, forKey: key)
            }
        }
        let collections = try await matcher.collections(
            of: Set(dogs.map(\.persistentModelID)), from: endedWalks, stored: stored, trackData: trackData)
        try Task.checkCancellation()
        byDog = collections
        emptyCaches()

        try recordCompleted(dogs: dogs)
    }

    private func emptyCaches() {
        pageCache = [:]
        cantonCache = [:]
    }

    /// Stores a record for each dog and area or street that the dog has
    /// completed and that has no record yet.
    private func recordCompleted(dogs: [Dog]) throws {
        let dogByID = Dictionary(dogs.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })

        let areaRecords = CollectionEngine.completedRecords(
            collections: byDog, areas: Array(areas.values), existing: dogs.flatMap(\.completedAreaRecords))
        for record in areaRecords {
            guard let dog = dogByID[record.dog] else { continue }
            context.insert(CompletedArea(dog: dog, area: record.goal, completedAt: record.date))
        }

        let streetRecords = CollectionEngine.completedRecords(
            collections: byDog, streets: streets.values.flatMap { $0 }, existing: dogs.flatMap(\.completedStreetRecords))
        for record in streetRecords {
            guard let dog = dogByID[record.dog] else { continue }
            context.insert(CompletedStreet(dog: dog, street: record.goal, completedAt: record.date))
        }

        // A completed record is permanent (ADR 0002), so it does not wait for
        // the autosave.
        if !areaRecords.isEmpty || !streetRecords.isEmpty {
            try context.save()
        }
    }

    fileprivate static func dogIDs(of walk: Walk) -> Set<PersistentIdentifier> {
        Set((walk.dogs ?? []).map(\.persistentModelID))
    }
}

/// The part of an update that runs off the main actor: it reads the map
/// packages and the stored matches, and matches the walks.
///
/// Each step opens its own packages, because other parts of the app read
/// the packages at the same time.
nonisolated private struct Matcher: Sendable {
    /// An ended walk as the matcher sees it: the key of its match and its dogs.
    struct EndedWalk: Sendable {
        let key: WalkMatchCache.Key
        let dogs: Set<PersistentIdentifier>
    }

    /// What the first step reads.
    struct Stored: Sendable {
        let cache: WalkMatchCache?
        let matches: [WalkMatchCache.Key: WalkMatch]
        /// The areas, the streets and the cantons, if the step loaded them.
        let loadedAreas: LoadedAreas?
    }

    struct LoadedAreas: Sendable {
        let areas: [Int: Area]
        let streets: [Int: [Street]]
        let cantons: [String]
    }

    let packageURLs: [URL]
    let cacheRoot: URL?

    /// The stored match of each walk that has one, and the areas and the
    /// streets if they are needed.
    @concurrent func stored(for keys: [WalkMatchCache.Key], loadsAreas: Bool) async throws -> Stored {
        let packages = try packageURLs.map(MapPackage.init(url:))
        let cache = cacheRoot.flatMap { root in
            WalkMatchCache.forPackages(zip(packageURLs, packages).map { (url: $0, mapRelease: $1.mapRelease) }, in: root)
        }
        var matches: [WalkMatchCache.Key: WalkMatch] = [:]
        for key in keys {
            matches[key] = cache?.match(for: key)
        }
        return Stored(cache: cache, matches: matches, loadedAreas: loadsAreas ? try Self.areas(of: packages) : nil)
    }

    private static func areas(of packages: [MapPackage]) throws -> LoadedAreas {
        let areas = try packages.flatMap { try $0.areas() }
        let streets = try packages.flatMap { try $0.streets() }
        return LoadedAreas(
            areas: Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            streets: Dictionary(grouping: streets, by: \.id.area),
            cantons: Set(areas.map(\.canton)).sorted())
    }

    /// The collection of each dog from all walks. It matches the walks that
    /// have no stored match, and stores their matches.
    ///
    /// A track that cannot be read collects nothing, as it shows as empty.
    /// Its match is not stored, so that the next update tries it again.
    @concurrent func collections(
        of dogs: Set<PersistentIdentifier>, from walks: [EndedWalk], stored: Stored,
        trackData: [WalkMatchCache.Key: Data?]
    ) async throws -> [PersistentIdentifier: DogCollection] {
        var matches = stored.matches
        if !trackData.isEmpty {
            let tracks = trackData.mapValues { data in data.flatMap { try? Track(data: $0) } }
            // The packages are too big to load at once, so the engine gets
            // only the segments that the walks can cover.
            let boxes = tracks.values.flatMap { CollectionEngine.coverableBoxes(of: $0 ?? Track()) }
            let packages = try packageURLs.map(MapPackage.init(url:))
            let engine = CollectionEngine(segments: try MapPackage.segments(in: boxes, of: packages))
            for (key, track) in tracks {
                try Task.checkCancellation()
                let match = engine.match(track ?? Track())
                matches[key] = match
                if track != nil {
                    stored.cache?.store(match, for: key)
                }
            }
        }
        try Task.checkCancellation()
        stored.cache?.removeAll(except: Set(walks.map(\.key)))
        return CollectionEngine.collections(
            of: dogs, from: walks.map { (dogs: $0.dogs, match: matches[$0.key] ?? WalkMatch()) })
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

#if DEBUG
extension Collections {
    /// Collections with an empty store and no map packages, for previews.
    static func preview() -> Collections {
        let container = try! ModelContainer(
            for: Dog.self, Walk.self, CompletedArea.self, CompletedStreet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return Collections(context: ModelContext(container), packageURLs: [], cacheRoot: nil)
    }
}
#endif

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

/// Updates the collections whenever the ended walks or their dogs change.
/// The app starts the first update at launch.
struct CollectionUpdates: ViewModifier {
    @Environment(Collections.self) private var collections
    @Query private var dogs: [Dog]
    /// A walk counts when it has ended. During a walk, `LiveFeedback` matches its points.
    @Query(filter: #Predicate<Walk> { $0.endedAt != nil }) private var walks: [Walk]

    func body(content: Content) -> some View {
        content
            .task(id: collectionInput) {
                await collections.update()
            }
    }

    /// What the collections depend on. A change starts a new update.
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
