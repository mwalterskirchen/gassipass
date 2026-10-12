//
//  Collections.swift
//  gassipass
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
///
/// The stored matches of the walks belong to one map release
/// (`WalkMatchCache`). So the first update after a new map release matches
/// all walks again: a removed segment leaves the collections, and a new
/// segment that old walks cover is collected at once. The completed records
/// stay.
///
/// The store keeps the collections of the last update (`WalkedSegment`), so
/// that the app shows them at once at launch. An update whose dogs, walks,
/// app build and map packages are the same as those of the stored
/// collections matches no walk.
@Observable
final class Collections {
    /// The collection of each dog, from the store or else empty until the
    /// first update.
    private(set) var byDog: [UUID: DogCollection] = [:]
    /// The ended walks of each dog that its collection is built from, from
    /// the store or else empty until the first update.
    private var walksByDog: [UUID: Set<UUID>] = [:]
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
    @ObservationIgnored private var cantonCache: [UUID?: String?] = [:]

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let matcher: Matcher
    @ObservationIgnored private var areasAreLoaded = false
    /// The update that runs now. A new update cancels it.
    @ObservationIgnored private var running: Task<Void, Never>?
    /// The version and the input of the collections in the store, and
    /// whether every walk had a match, or nil if the store has none.
    @ObservationIgnored private var storedBuild: (version: String, input: CollectionInput, matchedEveryWalk: Bool)?

    private static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "Collections")

    /// - Parameters:
    ///   - context: The store of the dogs, the walks and the completed records.
    ///   - packages: The map packages.
    ///   - cacheRoot: The folder for the stored matches of the walks, or nil
    ///     to store none.
    init(context: ModelContext, packages: MapPackages, cacheRoot: URL?) {
        self.context = context
        matcher = Matcher(packages: packages, cacheRoot: cacheRoot)
        loadStoredCollections()
    }

    func collection(of dog: UUID?) -> DogCollection {
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
        let dogs = try context.fetch(Dog.all())
        let walks = try context.fetch(Walk.ended())
        // The dogs of a walk can change while the update runs, so this reads
        // them together with the input of the matcher.
        let input = CollectionInput(dogs: dogs, walks: walks)
        let version = try await matcher.version()
        try Task.checkCancellation()
        // The stored collections are up to date, so no walk needs its match.
        let isStored = storedBuild.map { $0.matchedEveryWalk && $0.version == version && $0.input == input } ?? false
        let endedWalks = isStored ? [] : walks.compactMap { walk in
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
        if !isStored {
            let matchedEveryWalk = try await rebuild(from: walks, endedWalks: endedWalks, stored: stored, dogs: dogs)
            try storeCollections(version: version, input: input, matchedEveryWalk: matchedEveryWalk)
        }
        try recordCompleted(dogs: dogs)
    }

    /// Rebuilds the collections from the walks. It returns whether every
    /// walk has a match, which a walk without a readable track has not.
    private func rebuild(
        from walks: [Walk], endedWalks: [Matcher.EndedWalk], stored: Matcher.Stored, dogs: [Dog]
    ) async throws -> Bool {
        let walksByDog = Self.walkIDs(byDog: walks)
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
        let rebuilt = try await matcher.collections(
            of: Set(dogs.map(\.id)), from: endedWalks, stored: stored, trackData: trackData)
        try Task.checkCancellation()
        byDog = rebuilt.collections
        self.walksByDog = walksByDog
        emptyCaches()
        return rebuilt.matchedEveryWalk
    }

    /// Shows the collections of the last update until the first update ends.
    /// Collections that cannot be read are rebuilt by the first update.
    private func loadStoredCollections() {
        do {
            guard let build = try context.fetch(FetchDescriptor<CollectionBuild>()).first else { return }
            let input = try CollectionInput(data: build.input)
            var byDog = Dictionary(uniqueKeysWithValues: input.dogs.map { ($0, DogCollection()) })
            for segment in try context.fetch(FetchDescriptor<WalkedSegment>()) {
                byDog[segment.dogID]?.add(segment)
            }
            self.byDog = byDog
            walksByDog = input.walksByDog
            storedBuild = (build.version, input, build.matchedEveryWalk)
        } catch {
            Self.logger.error("The stored collections cannot be read: \(String(describing: error), privacy: .public)")
        }
    }

    /// Stores the collections for the next launch. It writes only the rows
    /// that changed.
    private func storeCollections(version: String, input: CollectionInput, matchedEveryWalk: Bool) throws {
        var rows: [WalkedSegmentKey: WalkedSegment] = [:]
        for row in try context.fetch(FetchDescriptor<WalkedSegment>()) {
            let key = WalkedSegmentKey(dog: row.dogID, segment: row.segmentID)
            if rows[key] == nil {
                rows[key] = row
            } else {
                context.delete(row)
            }
        }
        for (dog, collection) in byDog {
            for (segment, parts) in collection.coveredParts {
                let row = rows.removeValue(forKey: WalkedSegmentKey(dog: dog, segment: segment))
                    ?? insertedRow(dog: dog, segment: segment)
                row.update(coveredParts: parts, collected: collection.collected[segment])
            }
        }
        for row in rows.values {
            context.delete(row)
        }
        let data = try input.data()
        let build = try context.fetch(FetchDescriptor<CollectionBuild>()).first ?? {
            let build = CollectionBuild()
            context.insert(build)
            return build
        }()
        build.version = version
        build.input = data
        build.matchedEveryWalk = matchedEveryWalk
        try context.save()
        storedBuild = (version, input, matchedEveryWalk)
    }

    private func insertedRow(dog: UUID, segment: Segment.ID) -> WalkedSegment {
        let row = WalkedSegment(dogID: dog, segmentID: segment)
        context.insert(row)
        return row
    }

    private func emptyCaches() {
        pageCache = [:]
        cantonCache = [:]
    }

    /// Stores a record for each dog and area or street that the dog has
    /// completed and that has no record yet, and merges the records that
    /// were stored for the same dog and goal.
    private func recordCompleted(dogs: [Dog]) throws {
        let deletedDuplicates = mergeRecords(of: dogs)
        let dogByID = Dictionary(dogs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let areaRecords = CollectionEngine.completedRecords(
            collections: byDog, areas: Array(areas.values), existing: dogs.flatMap(\.completedAreaRecords))
        for record in areaRecords {
            guard let dog = dogByID[record.dog] else { continue }
            _ = CompletedArea(dog: dog, area: record.goal, completedAt: record.date, context: context)
        }

        let streetRecords = CollectionEngine.completedRecords(
            collections: byDog, streets: streets.values.flatMap { $0 }, existing: dogs.flatMap(\.completedStreetRecords))
        for record in streetRecords {
            guard let dog = dogByID[record.dog] else { continue }
            _ = CompletedStreet(dog: dog, street: record.goal, completedAt: record.date, context: context)
        }

        // A completed record is permanent (ADR 0002).
        if deletedDuplicates || !areaRecords.isEmpty || !streetRecords.isEmpty {
            try context.save()
        }
    }

    /// Two phones can each store a record for the same dog and area or
    /// street before the records of one phone reach the other. This keeps
    /// the record with the earliest date and deletes the others. It returns
    /// whether it deleted a record.
    private func mergeRecords(of dogs: [Dog]) -> Bool {
        var deleted = false
        for dog in dogs {
            let areas = Dictionary(grouping: dog.shownCompletedAreas, by: \.area)
            deleted = deleteAllButEarliest(areas.values, order: { ($0.completedAt, $0.id.uuidString) }) || deleted
            let streets = Dictionary(grouping: dog.shownCompletedStreets, by: \.streetID)
            deleted = deleteAllButEarliest(streets.values, order: { ($0.completedAt, $0.id.uuidString) }) || deleted
        }
        return deleted
    }

    /// Deletes all records of each group but the first in the order. The
    /// order must be the same on every phone, or two phones could each
    /// keep a different record, and both records would then be deleted.
    private func deleteAllButEarliest<Record: UploadingRow>(
        _ groups: some Sequence<[Record]>, order: (Record) -> (Date, String)
    ) -> Bool {
        var deleted = false
        for records in groups where records.count > 1 {
            let earliest = records.min { order($0) < order($1) }
            for record in records where record !== earliest {
                record.markDeleted()
                deleted = true
            }
        }
        return deleted
    }

    fileprivate static func dogIDs(of walk: Walk) -> Set<UUID> {
        Set(walk.dogs.map(\.id))
    }

    private static func walkIDs(byDog walks: [Walk]) -> [UUID: Set<UUID>] {
        var walkIDs: [UUID: Set<UUID>] = [:]
        for walk in walks {
            for dog in dogIDs(of: walk) {
                walkIDs[dog, default: []].insert(walk.id)
            }
        }
        return walkIDs
    }
}

/// The part of an update that runs off the main actor: it reads the map
/// packages and the stored matches, and matches the walks.
nonisolated private struct Matcher: Sendable {
    /// An ended walk as the matcher sees it: the key of its match and its dogs.
    struct EndedWalk: Sendable {
        let key: WalkMatchCache.Key
        let dogs: Set<UUID>
    }

    /// What the first step reads.
    struct Stored: Sendable {
        let cache: WalkMatchCache?
        let matches: [WalkMatchCache.Key: WalkMatch]
        /// The areas, the streets and the cantons, if the step loaded them.
        let loadedAreas: LoadedAreas?
    }

    /// The collections from a rebuild, and whether every walk has a match.
    /// A walk whose track cannot be read has none.
    struct Rebuilt: Sendable {
        let collections: [UUID: DogCollection]
        let matchedEveryWalk: Bool
    }

    struct LoadedAreas: Sendable {
        let areas: [Int: Area]
        let streets: [Int: [Street]]
        let cantons: [String]
    }

    let packages: MapPackages
    let cacheRoot: URL?

    /// The version of the collections: the build of the app and the map
    /// packages.
    @concurrent func version() async throws -> String {
        CacheFolder.version(packages: try packages.identity())
    }

    /// The stored match of each walk that has one, and the areas and the
    /// streets if they are needed.
    @concurrent func stored(for keys: [WalkMatchCache.Key], loadsAreas: Bool) async throws -> Stored {
        let identity = try packages.identity()
        let cache = cacheRoot.flatMap { WalkMatchCache.forPackages(identity, in: $0) }
        var matches: [WalkMatchCache.Key: WalkMatch] = [:]
        for key in keys {
            matches[key] = cache?.match(for: key)
        }
        return Stored(cache: cache, matches: matches, loadedAreas: loadsAreas ? try loadAreas() : nil)
    }

    private func loadAreas() throws -> LoadedAreas {
        let areas = try packages.areas()
        let streets = try packages.streets()
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
        of dogs: Set<UUID>, from walks: [EndedWalk], stored: Stored,
        trackData: [WalkMatchCache.Key: Data?]
    ) async throws -> Rebuilt {
        var matches = stored.matches
        var matchedEveryWalk = true
        if !trackData.isEmpty {
            let tracks = trackData.mapValues { data in data.flatMap { try? Track(data: $0) } }
            matchedEveryWalk = !tracks.values.contains(nil)
            let engine = try packages.engine(covering: tracks.values.compactMap { $0 })
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
        let collections = CollectionEngine.collections(
            of: dogs, from: walks.map { (dogs: $0.dogs, match: matches[$0.key] ?? WalkMatch()) })
        return Rebuilt(collections: collections, matchedEveryWalk: matchedEveryWalk)
    }
}

extension Collections {
    /// The pages of every area of the canton for the dog, for the collection
    /// book. The book shows many areas, so the pages are built only when the
    /// areas, the collections or the records of the dog change.
    func pages(canton: String, for dog: Dog) -> [CollectionBook.Page] {
        // These reads come first, so that the screen observes the areas and
        // the collection also when the cache holds the pages. The screen sees
        // new records through its fetch request of the dogs.
        let areas = areas
        let collection = collection(of: dog.id)
        let records = dog.completedAreaRecords
        let key = PageKey(canton: canton, dog: dog.id, records: records)
        if let pages = pageCache[key] { return pages }
        let pages = CollectionBook.pages(
            canton: canton, areas: Array(areas.values), collection: collection,
            dog: dog.id, records: records)
        pageCache[key] = pages
        return pages
    }

    /// The canton where the dog has collected the most segments, or nil if
    /// the dog has collected none.
    func cantonWithMostCollected(by dog: UUID?) -> String? {
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

    /// The totals of the dog, for the home screen, or nil until an update
    /// has built the collection of the dog.
    func totals(of dog: Dog) -> DogTotals? {
        guard let collection = byDog[dog.id] else { return nil }
        return DogTotals(
            collection: collection, dog: dog.id,
            areaRecords: dog.completedAreaRecords, streetRecords: dog.completedStreetRecords)
    }

    /// The number of segments that the dog collected during the walk, for
    /// the home screen, or nil until an update has built the collection of
    /// the dog with the walk. A walk that has just ended, or a walk that a
    /// dog has just joined, has no count until the next update ends.
    func collectedSegmentCount(during walk: Walk, of dog: Dog) -> Int? {
        guard let endedAt = walk.endedAt, let collection = byDog[dog.id],
              walksByDog[dog.id]?.contains(walk.id) == true
        else { return nil }
        return collection.collectedSegmentCount(during: walk.startedAt...endedAt)
    }

    /// The feature IDs of the segments that the walk collected for at least
    /// one of its dogs, for the map of the walk. It is empty until an update
    /// has built the collections with the walk.
    func collectedFeatures(during walk: Walk) -> Set<Int> {
        guard let endedAt = walk.endedAt else { return [] }
        var features: Set<Int> = []
        for dog in walk.dogs {
            guard let collection = byDog[dog.id],
                  walksByDog[dog.id]?.contains(walk.id) == true
            else { continue }
            features.formUnion(collection.collectedFeatures(during: walk.startedAt...endedAt))
        }
        return features
    }

    /// The pages of the pinned areas for the dog, for the home screen.
    func pinnedPages(_ pinned: [Area.ID], for dog: Dog) -> [CollectionBook.Page] {
        CollectionBook.pinnedPages(
            pinned: pinned, areas: Array(areas.values), collection: collection(of: dog.id),
            dog: dog.id, records: dog.completedAreaRecords)
    }
}

extension Collections {
    /// Collections with an empty store and no map packages, for previews.
    static func preview(context: ModelContext = .preview) -> Collections {
        Collections(context: context, packages: MapPackages(urls: []), cacheRoot: nil)
    }
}

extension ModelContainer {
    /// An empty in-memory store, for previews.
    static let preview = try! LocalStore.inMemory()
}

extension ModelContext {
    /// The context of the store for previews.
    static var preview: ModelContext {
        ModelContainer.preview.mainContext
    }
}

extension Dog {
    /// The completed records of the areas of the dog that are not deleted.
    /// They come from the relationship, which changes at once when a record
    /// is inserted.
    fileprivate var shownCompletedAreas: [CompletedArea] {
        (completedAreas ?? []).filter { $0.deletedAt == nil }
    }

    fileprivate var shownCompletedStreets: [CompletedStreet] {
        (completedStreets ?? []).filter { $0.deletedAt == nil }
    }

    /// The stored completed records of the areas of the dog.
    var completedAreaRecords: [CompletedRecord<UUID, Area.ID>] {
        shownCompletedAreas.map {
            CompletedRecord(dog: id, goal: $0.area, date: $0.completedAt)
        }
    }

    /// The stored completed records of the streets of the dog.
    var completedStreetRecords: [CompletedRecord<UUID, Street.ID>] {
        shownCompletedStreets.map {
            CompletedRecord(dog: id, goal: $0.streetID, date: $0.completedAt)
        }
    }
}

/// Updates the collections whenever the dogs, the ended walks, their dogs or
/// the completed records change. The app starts the first update at launch.
struct CollectionUpdates: ViewModifier {
    @Environment(Collections.self) private var collections
    @Query(Dog.all()) private var dogs: [Dog]
    /// A walk counts when it has ended. During a walk, `CurrentWalk` matches its points.
    @Query(Walk.ended()) private var walks: [Walk]
    /// The update merges two records of the same dog and goal.
    @Query private var completedAreas: [CompletedArea]
    @Query private var completedStreets: [CompletedStreet]

    func body(content: Content) -> some View {
        content
            .task(id: updateInput) {
                await collections.update()
            }
    }

    /// What an update depends on. A change starts a new update.
    private var updateInput: UpdateInput {
        UpdateInput(
            collections: CollectionInput(dogs: dogs, walks: walks),
            recordCount: completedAreas.count + completedStreets.count)
    }
}

private struct PageKey: Hashable {
    let canton: String
    let dog: UUID
    let records: [CompletedRecord<UUID, Area.ID>]
}

private struct UpdateInput: Equatable {
    let collections: CollectionInput
    let recordCount: Int
}

/// What the collections are built from: the dogs, and the ended walks with
/// their dogs.
nonisolated private struct CollectionInput: Codable, Equatable, Sendable {
    let dogs: Set<UUID>
    let walks: [WalkInput]

    @MainActor
    init(dogs: [Dog], walks: [Walk]) {
        self.dogs = Set(dogs.map(\.id))
        self.walks = walks.map {
            WalkInput(walk: $0.id, key: WalkMatchCache.Key($0), dogs: Collections.dogIDs(of: $0))
        }
    }

    init(data: Data) throws {
        self = try PropertyListDecoder().decode(Self.self, from: data)
    }

    func data() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    /// The ended walks of each dog.
    var walksByDog: [UUID: Set<UUID>] {
        var walkIDs: [UUID: Set<UUID>] = [:]
        for walk in walks {
            for dog in walk.dogs {
                walkIDs[dog, default: []].insert(walk.walk)
            }
        }
        return walkIDs
    }
}

nonisolated private struct WalkInput: Codable, Equatable, Sendable {
    let walk: UUID
    /// The key of the match changes when the track of the walk arrives after
    /// the walk, or when the distance is calculated again.
    let key: WalkMatchCache.Key?
    let dogs: Set<UUID>
}

/// A row of the stored collections: one dog and one segment.
private struct WalkedSegmentKey: Hashable {
    let dog: UUID
    let segment: Segment.ID
}

extension DogCollection {
    /// Adds the stored segment.
    fileprivate mutating func add(_ segment: WalkedSegment) {
        coveredParts[segment.segmentID] = CoveredParts(data: segment.coveredParts)
        if let collectedAt = segment.collectedAt {
            collected[segment.segmentID] = CollectedSegment(
                fid: segment.fid, area: segment.area,
                street: segment.streetName.map { Street.ID(area: segment.area, name: $0) },
                lengthMetres: segment.lengthMetres, collectedAt: collectedAt)
        }
    }
}

extension WalkedSegment {
    /// Gives the row the covered parts and the collected segment. It writes
    /// only the values that changed, so that an unchanged row is not saved.
    fileprivate func update(coveredParts parts: CoveredParts, collected: CollectedSegment?) {
        let data = parts.data
        if coveredParts != data { coveredParts = data }
        if collectedAt != collected?.collectedAt { collectedAt = collected?.collectedAt }
        guard let collected else { return }
        if fid != collected.fid { fid = collected.fid }
        if area != collected.area { area = collected.area }
        if streetName != collected.street?.name { streetName = collected.street?.name }
        if lengthMetres != collected.lengthMetres { lengthMetres = collected.lengthMetres }
    }
}
