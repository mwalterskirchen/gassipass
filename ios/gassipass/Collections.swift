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
/// the streets, adds the new ended walks to the collection of each dog
/// (`CollectionHistory`), or rebuilds it from all its ended walks when a walk
/// left it (ADR 0002), stores each new completed record, area step and ring stamp,
/// and stores the weekly goals that the dogs have finished. The app calls
/// it at launch, also when Core Location launches the app in the background
/// during a walk, and `CollectionUpdates` calls it whenever the ended walks
/// or their dogs change.
///
/// The stored matches of the walks belong to one map release
/// (`WalkMatchCache`). So the first update after a new map release matches
/// all walks again: a removed segment leaves the collections, and a new
/// segment that old walks cover is collected at once. The completed records
/// stay.
///
/// The store keeps the collections of the last update and their history
/// (`WalkedSegment`, `CollectionBuild`), so that the app shows them at once
/// at launch, and its first update adds only the new walks. An update whose
/// dogs, walks, app build and map packages are the same as those of the
/// stored collections matches no walk.
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
    /// The area steps of all dogs from the store, which are not deleted.
    private(set) var stepRecords: [CompletedRecord<UUID, AreaStepID>] = []
    /// The ring stamps of all dogs from the store, which are not deleted.
    private(set) var ringRecords: [CompletedRecord<UUID, Ring>] = []
    /// The home base of the pack at the last update, or nil.
    private(set) var homeBase: HomeBase?
    /// The segments around the home base that the rings of the last update
    /// needed, or nil until they are loaded. They hold the current ring of
    /// each dog and the ring after it, so that the map has new segments
    /// beyond the current ring, and a walk that completes the current ring
    /// has the next one.
    private(set) var ringSegments: RingSegments?
    /// The number of new stamps that each dog got from its earlier walks,
    /// at the first update after the app got the area steps, or nil when
    /// there is nothing to show. A dog with no new stamp has no entry.
    private(set) var earlierStamps: [UUID: Int]?
    /// The sets of weekly goals of all dogs from the store, which are not
    /// deleted, as the last update left them.
    var goalSets: [WeeklyGoalSet] = []

    /// The pages that the collection book has built, by canton, dog and
    /// records. A new load of the areas or a new collection empties it.
    @ObservationIgnored private var pageCache: [PageKey: [CollectionBook.Page]] = [:]
    /// The canton where each dog has collected the most segments, for the
    /// collection book. A new load of the areas or a new collection empties it.
    @ObservationIgnored private var cantonCache: [UUID?: String?] = [:]

    @ObservationIgnored let context: ModelContext
    @ObservationIgnored private let matcher: Matcher
    /// The clock of the weekly goals.
    @ObservationIgnored let now: () -> Date
    /// The notifications of the weekly goals, or nil to schedule none.
    @ObservationIgnored let reminders: GoalReminders?
    /// The segments that each recent ended walk alone marked
    /// (`WalkMatch.Entry.markedAt`), for the weekly goals. It holds the walks
    /// that started at most `goalWeeks` weeks before the current week.
    @ObservationIgnored var walkMarks: [WalkMatchCache.Key: [Segment.ID: Date]] = [:]
    /// Whether an update has built the collections and loaded the areas, so
    /// that the app can make the weekly goals.
    @ObservationIgnored private(set) var hasUpdated = false
    /// Whether the app has asked for the weekly goals of the current week,
    /// and the next update that ends makes them (`makeWeeklyGoals()`).
    @ObservationIgnored var areGoalSetsDue = false
    /// The user defaults that note that the stamps from earlier walks were
    /// counted, or nil to count none.
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var areasAreLoaded = false
    /// The update that runs now. A new update cancels it.
    @ObservationIgnored private var running: Task<Void, Never>?
    /// The history of the collections and its version, from the store or
    /// the last update, or nil if neither has one.
    @ObservationIgnored private var history: (version: String, history: CollectionHistory)?
    /// The version and the input of the collections in the store, and
    /// whether every walk had a match, or nil if the store has none.
    @ObservationIgnored private var storedBuild: (version: String, input: CollectionInput, matchedEveryWalk: Bool)?
    /// The history of each dog as the rows of the store have it, so that a
    /// store writes only the rows that changed since. It is nil when the
    /// store can differ from it, for example after a failed store or in a
    /// store from before the history, and the next store then writes every
    /// row.
    @ObservationIgnored private var storedHistories: [UUID: CoverageHistory]?

    private static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "Collections")
    /// Marks the load and the store of the collections, for Instruments.
    private static let signposter = OSSignposter(logger: logger)

    /// - Parameters:
    ///   - context: The store of the dogs, the walks and the completed records.
    ///   - packages: The map packages.
    ///   - cacheRoot: The folder for the stored matches of the walks, or nil
    ///     to store none.
    ///   - defaults: The user defaults that note that the stamps from earlier
    ///     walks were counted, or nil to count none.
    ///   - reminders: The notifications of the weekly goals, or nil to
    ///     schedule none.
    ///   - now: The clock of the weekly goals.
    init(
        context: ModelContext, packages: MapPackages, cacheRoot: URL?, defaults: UserDefaults? = nil,
        reminders: GoalReminders? = nil, now: @escaping () -> Date = { .now }
    ) {
        self.context = context
        matcher = Matcher(packages: packages, cacheRoot: cacheRoot)
        self.defaults = defaults
        self.reminders = reminders
        self.now = now
        earlierStamps = Self.earlierStampsToShow(in: defaults)
        loadStoredCollections()
        do {
            stepRecords = try Self.records(of: context.fetch(Self.shownAreaSteps))
            let dogIDs = Set(try context.fetch(Dog.all()).map(\.id))
            ringRecords = Self.ringRecords(of: try context.fetch(Self.shownRings), dogs: dogIDs)
            homeBase = try Pack.ofThisPhone(in: context)?.homeBase
            goalSets = try Self.storedGoalSets(in: context)
        } catch {
            Self.logger.error("The records cannot be read: \(String(describing: error), privacy: .public)")
        }
    }

    func collection(of dog: UUID?) -> DogCollection {
        dog.flatMap { byDog[$0] } ?? DogCollection()
    }

    /// The area steps of the dog.
    func stepRecords(of dog: UUID) -> [CompletedRecord<UUID, AreaStepID>] {
        stepRecords.filter { $0.dog == dog }
    }

    /// The ring stamps of the dog, around any home base.
    func ringRecords(of dog: UUID) -> [CompletedRecord<UUID, Ring>] {
        ringRecords.filter { $0.dog == dog }
    }

    /// The level of the dog: the highest ring of its ring stamps.
    func level(of dog: UUID) -> Int {
        CollectionEngine.level(of: dog, records: ringRecords)
    }

    /// The current ring of the dog around the home base, or nil without a
    /// home base.
    func currentRing(of dog: UUID) -> Ring? {
        homeBase.map {
            CollectionEngine.currentRing(of: dog, around: $0, records: ringRecords, skippingEmptyIn: ringSegments)
        }
    }

    /// The current ring of the dog with its completion, its marked share at
    /// the date and the nearest new segments, for the ring card, or nil
    /// without a home base and until an update has loaded the segments of
    /// the ring.
    func ringStatus(of dog: UUID, at now: Date = .now) -> RingStatus? {
        guard let ring = currentRing(of: dog), let ringSegments, ringSegments.holds(ring) else { return nil }
        let collection = collection(of: dog)
        return RingStatus(
            ring: ring, completion: ringSegments.completion(of: ring, for: collection),
            markedShare: ringSegments.markedShare(of: ring, for: collection, at: now),
            nearestNewSegments: ringSegments.nearestNewSegments(
                for: collection, count: RingStatus.nearestNewSegmentCount))
    }

    /// Notes that the app has shown the stamps from earlier walks.
    func noteEarlierStampsShown() {
        earlierStamps = nil
        defaults?.removeObject(forKey: Self.earlierStampsToShowKey)
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

    /// Waits for the update that runs now, if any.
    func waitForUpdate() async {
        await running?.value
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
        // One identity for the whole update, so that the version, the history
        // and the stored matches belong to the same map packages.
        let identity = try await matcher.identity()
        let version = CacheFolder.version(packages: identity)
        try Task.checkCancellation()
        // The stored collections are up to date, so no walk needs its match.
        let isStored = storedBuild.map { $0.matchedEveryWalk && $0.version == version && $0.input == input } ?? false
        let plan = isStored ? nil : try await matcher.plan(
            for: input, history: history.flatMap { $0.version == version ? $0.history : nil })
        try Task.checkCancellation()

        let stored = try await matcher.stored(
            for: plan.map { $0.additions.map(\.key) } ?? [], loadsAreas: !areasAreLoaded, identity: identity)
        try Task.checkCancellation()
        if let loaded = stored.loadedAreas {
            areas = loaded.areas
            streets = loaded.streets
            cantons = loaded.cantons
            areasAreLoaded = true
            // New map packages have other segments around the home base.
            ringSegments = nil
            emptyCaches()
        }
        let marksSince = Self.goalWindowStart(at: now())
        var matchedEveryWalk: Bool?
        if let plan {
            matchedEveryWalk = try await rebuild(
                from: walks, plan: plan, version: version, stored: stored, marksSince: marksSince)
        }
        // The records are permanent and the stored collections are only a
        // cache, so the records come first.
        let newAreaRecords = try recordCompleted(dogs: dogs)
        do {
            try await recordRings(dogs: dogs)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The rings wait for the next update, and the rest of this one
            // goes on, so that the walks and their summaries do not wait.
            Self.logger.error("The rings cannot update: \(String(describing: error), privacy: .public)")
        }
        countEarlierStamps(newAreaRecords: newAreaRecords)
        try await loadWalkMarks(of: walks, since: marksSince)
        try updateGoals(dogs: dogs, walks: walks)
        if let matchedEveryWalk {
            // A walk counts as built only now, so that its summary waits for
            // the records of its stamps and goals (`summary(of:)`).
            walksByDog = input.walksByDog
            try storeCollections(
                version: version, input: input, history: history?.history ?? CollectionHistory(),
                matchedEveryWalk: matchedEveryWalk)
        }
        hasUpdated = areasAreLoaded
        if hasUpdated {
            makeDueGoalSets()
        }
    }

    /// The marks of the ended walks from their stored matches, for the
    /// replay of the weekly goals (`GoalReplay`). A walk without a stored
    /// match has none.
    func storedMarks(of walks: [Walk]) async throws -> [WalkMatchCache.Key: [Segment.ID: Date]] {
        try await matcher.marks(for: walks.compactMap(WalkMatchCache.Key.init))
    }

    /// Keeps the marks of the ended walks that started at the date or later,
    /// and reads from the stored matches those that it does not have.
    private func loadWalkMarks(of walks: [Walk], since date: Date) async throws {
        let keys = Set(walks.compactMap { walk in WalkMatchCache.Key(walk).flatMap { $0.startedAt >= date ? $0 : nil } })
        walkMarks = walkMarks.filter { keys.contains($0.key) }
        let missing = keys.filter { walkMarks[$0] == nil }
        guard !missing.isEmpty else { return }
        let read = try await matcher.marks(for: Array(missing))
        try Task.checkCancellation()
        walkMarks.merge(read) { first, _ in first }
    }

    /// The key in the user defaults that notes that the stamps from earlier
    /// walks were counted.
    private static let earlierStampsKey = "countedEarlierStamps"
    /// The key in the user defaults of the counts that wait to show, by the
    /// ID of the dog. The update that counts them can run in the background,
    /// so they wait for a launch that shows them.
    private static let earlierStampsToShowKey = "earlierStampsToShow"

    /// Counts the new stamps of each dog from its earlier walks, once: the
    /// area steps, and the areas that the dog completed only by the rule of
    /// 95%, which this update recorded. It waits for the areas, because the
    /// steps need them.
    private func countEarlierStamps(newAreaRecords: [CompletedRecord<UUID, Area.ID>]) {
        guard let defaults, !defaults.bool(forKey: Self.earlierStampsKey), areasAreLoaded else { return }
        var counts: [String: Int] = [:]
        for dog in stepRecords.map(\.dog) + newAreaRecords.map(\.dog) {
            counts[dog.uuidString, default: 0] += 1
        }
        if !counts.isEmpty {
            defaults.set(counts, forKey: Self.earlierStampsToShowKey)
        }
        defaults.set(true, forKey: Self.earlierStampsKey)
        earlierStamps = Self.earlierStampsToShow(in: defaults)
    }

    /// The counts of the stamps from earlier walks that wait to show, or nil.
    private static func earlierStampsToShow(in defaults: UserDefaults?) -> [UUID: Int]? {
        guard let stored = defaults?.dictionary(forKey: earlierStampsToShowKey) as? [String: Int] else { return nil }
        let counts = Dictionary(
            stored.compactMap { key, count in UUID(uuidString: key).map { ($0, count) } },
            uniquingKeysWith: +)
        return counts.isEmpty ? nil : counts
    }

    /// Adds the walks of the plan to the collections. It returns whether
    /// every walk has a match, which a walk without a readable track has not.
    /// The caller then notes the walks of each dog (`walksByDog`).
    private func rebuild(
        from walks: [Walk], plan: Matcher.Plan, version: String, stored: Matcher.Stored, marksSince: Date
    ) async throws -> Bool {
        // Only the new walks without a stored match read their track, which
        // is stored outside the database.
        let added = Set(plan.additions.map(\.key))
        var trackData: [WalkMatchCache.Key: Data?] = [:]
        for walk in walks {
            if let key = WalkMatchCache.Key(walk), added.contains(key), stored.matches[key] == nil {
                // Also a walk with no track data yet gets an entry, so that
                // it collects nothing until its track arrives.
                trackData.updateValue(walk.trackData, forKey: key)
            }
        }
        let rebuilt = try await matcher.collections(
            adding: plan, stored: stored, trackData: trackData, marksSince: marksSince)
        try Task.checkCancellation()
        byDog = rebuilt.history.collections
        history = (version, rebuilt.history)
        walkMarks.merge(rebuilt.marks) { _, rebuilt in rebuilt }
        emptyCaches()
        return rebuilt.matchedEveryWalk
    }

    /// Shows the collections of the last update until the first update ends.
    /// Collections that cannot be read are rebuilt by the first update.
    private func loadStoredCollections() {
        let interval = Self.signposter.beginInterval("Load stored collections")
        defer { Self.signposter.endInterval("Load stored collections", interval) }
        do {
            guard let build = try context.fetch(FetchDescriptor<CollectionBuild>()).first else { return }
            let input = try CollectionInput(data: build.input)
            var byDog = Dictionary(uniqueKeysWithValues: input.dogs.map { ($0, DogCollection()) })
            var entries = Dictionary(uniqueKeysWithValues: input.dogs.map { ($0, [Segment.ID: CoverageHistory.Entry]()) })
            var hasEveryRow = true
            var rowsFollowTheirHistory = true
            for segment in try context.fetch(FetchDescriptor<WalkedSegment>()) {
                if byDog[segment.dogID] == nil {
                    hasEveryRow = false
                }
                byDog[segment.dogID]?.add(segment)
                let entry = segment.historyEntry
                entries[segment.dogID]?[segment.segmentID] = entry
                if entry.parts != CoveredParts(data: segment.coveredParts) || entry.collectedAt != segment.collectedAt {
                    rowsFollowTheirHistory = false
                }
            }
            self.byDog = byDog
            walksByDog = input.walksByDog
            storedBuild = (build.version, input, build.matchedEveryWalk)
            // A store from before the history has no held walks, and its
            // first update builds the history from all walks. So does a store
            // with a row that its history did not write.
            if rowsFollowTheirHistory, let heldWalks = try? CollectionHistory.heldWalks(from: build.heldWalks) {
                let histories = entries.mapValues(CoverageHistory.init(entries:))
                history = (build.version, CollectionHistory(dogs: histories, walks: heldWalks))
                // A row of a dog that the input does not know is not in the
                // collections, so only a store that writes every row deletes it.
                storedHistories = hasEveryRow ? histories : nil
            }
        } catch {
            Self.logger.error("The stored collections cannot be read: \(String(describing: error), privacy: .public)")
        }
    }

    /// Stores the collections and their history for the next launch. It
    /// writes only the rows that changed.
    private func storeCollections(
        version: String, input: CollectionInput, history: CollectionHistory, matchedEveryWalk: Bool
    ) throws {
        let interval = Self.signposter.beginInterval("Store collections")
        defer { Self.signposter.endInterval("Store collections", interval) }
        let stored = storedHistories
        // A store that fails can leave rows that the memory does not know.
        storedHistories = nil
        if let stored {
            try storeChangedRows(of: history.dogs, since: stored)
        } else {
            try storeEveryRow(of: history.dogs)
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
        build.heldWalks = try history.heldWalksData()
        try context.save()
        storedBuild = (version, input, matchedEveryWalk)
        storedHistories = history.dogs
    }

    /// Writes the row of each segment whose history changed since the last
    /// store, and deletes the row of each segment that left a history. A new
    /// walk changes some segments, so it fetches only their rows. The kept
    /// intervals of a segment can change without its covered parts, when a
    /// walk is older than the others, so the rows follow the history.
    private func storeChangedRows(
        of histories: [UUID: CoverageHistory], since stored: [UUID: CoverageHistory]
    ) throws {
        var changed: Set<WalkedSegmentKey> = []
        for dog in Set(stored.keys).union(histories.keys) {
            let old = stored[dog]?.entries ?? [:]
            let new = histories[dog]?.entries ?? [:]
            for segment in Set(old.keys).union(new.keys) where old[segment] != new[segment] {
                changed.insert(WalkedSegmentKey(dog: dog, segment: segment))
            }
        }
        guard !changed.isEmpty else { return }
        let dogIDs = Set(changed.map(\.dog))
        let segmentIDs = Set(changed.map(\.segment))
        var rows: [WalkedSegmentKey: WalkedSegment] = [:]
        for row in try context.fetch(FetchDescriptor<WalkedSegment>(predicate: #Predicate {
            dogIDs.contains($0.dogID) && segmentIDs.contains($0.segmentID)
        })) {
            let key = WalkedSegmentKey(dog: row.dogID, segment: row.segmentID)
            guard changed.contains(key) else { continue }
            if rows[key] == nil {
                rows[key] = row
            } else {
                context.delete(row)
            }
        }
        for key in changed {
            if let entry = histories[key.dog]?.entries[key.segment] {
                let row = rows[key] ?? insertedRow(dog: key.dog, segment: key.segment)
                row.update(entry)
            } else if let row = rows[key] {
                context.delete(row)
            }
        }
    }

    /// Writes the row of each segment of the histories, and deletes every
    /// other row, also a second row of the same dog and segment.
    private func storeEveryRow(of histories: [UUID: CoverageHistory]) throws {
        var rows: [WalkedSegmentKey: WalkedSegment] = [:]
        for row in try context.fetch(FetchDescriptor<WalkedSegment>()) {
            let key = WalkedSegmentKey(dog: row.dogID, segment: row.segmentID)
            if rows[key] == nil {
                rows[key] = row
            } else {
                context.delete(row)
            }
        }
        for (dog, history) in histories {
            for (segment, entry) in history.entries {
                let row = rows.removeValue(forKey: WalkedSegmentKey(dog: dog, segment: segment))
                    ?? insertedRow(dog: dog, segment: segment)
                row.update(entry)
            }
        }
        for row in rows.values {
            context.delete(row)
        }
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
    /// completed, and for each area step that the dog has reached, that has
    /// no record yet, and merges the records that were stored for the same
    /// dog and goal. It returns the new records of completed areas.
    private func recordCompleted(dogs: [Dog]) throws -> [CompletedRecord<UUID, Area.ID>] {
        let steps = try context.fetch(Self.shownAreaSteps)
        // Both merges run, also when the first one deletes a record.
        let deletedRecords = mergeRecords(of: dogs)
        let deletedDuplicates = mergeSteps(steps) || deletedRecords
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

        // A record of a deleted dog does not count.
        let existingSteps = Self.records(of: steps.filter { $0.deletedAt == nil && dogByID[$0.dogID] != nil })
        let stepRecords = CollectionEngine.stepRecords(
            collections: byDog, areas: Array(areas.values), existing: existingSteps)
        for record in stepRecords {
            guard let dog = dogByID[record.dog] else { continue }
            _ = AreaStep(
                dog: dog, area: record.goal.area, step: record.goal.step, reachedAt: record.date, context: context)
        }

        // A completed record is permanent (ADR 0002).
        if deletedDuplicates || !areaRecords.isEmpty || !streetRecords.isEmpty || !stepRecords.isEmpty {
            try context.save()
        }
        self.stepRecords = existingSteps + stepRecords
        return areaRecords
    }

    /// Stores a ring stamp for each dog and ring around the home base that
    /// the dog has completed and that has no stamp yet, and merges the
    /// stamps that were stored for the same dog and ring. It loads the
    /// segments up to the ring after the current ring of each dog, also
    /// after a new stamp.
    private func recordRings(dogs: [Dog]) async throws {
        let rows = try context.fetch(Self.shownRings)
        let deletedDuplicates = mergeRings(rows)
        let dogIDs = Set(dogs.map(\.id))
        var records = Self.ringRecords(of: rows, dogs: dogIDs)
        let homeBase = try Pack.ofThisPhone(in: context)?.homeBase
        var newRecords: [CompletedRecord<UUID, Ring>] = []
        if let homeBase {
            let collections = byDog.filter { dogIDs.contains($0.key) }
            while true {
                let outermost = dogIDs
                    .map {
                        CollectionEngine.currentRing(
                            of: $0, around: homeBase, records: records, skippingEmptyIn: ringSegments)
                    }
                    .max { $0.number < $1.number } ?? Ring(number: 1, centre: homeBase)
                if ringSegments?.holds(outermost.next) != true {
                    let loaded = try await matcher.ringSegments(
                        around: homeBase, withinMetres: outermost.next.radiusMetres)
                    try Task.checkCancellation()
                    ringSegments = loaded
                    // The new segments can skip an empty ring, which moves
                    // the current ring out.
                    continue
                }
                guard let ringSegments else { break }
                let new = CollectionEngine.ringRecords(collections: collections, around: ringSegments, existing: records)
                guard !new.isEmpty else { break }
                records += new
                newRecords += new
            }
        }
        for record in newRecords {
            _ = CompletedRing(dogID: record.dog, ring: record.goal, completedAt: record.date, context: context)
        }
        // A ring stamp is permanent (ADR 0002).
        if deletedDuplicates || !newRecords.isEmpty {
            try context.save()
        }
        self.homeBase = homeBase
        ringRecords = records
    }

    /// The ring stamps that are not deleted.
    private static let shownRings = FetchDescriptor<CompletedRing>(predicate: #Predicate { $0.deletedAt == nil })

    /// The records of the ring stamps of the dogs that are not deleted, and
    /// of two stamps of the same dog and ring only the one that
    /// `mergeRings(_:)` keeps.
    private static func ringRecords(of rows: [CompletedRing], dogs: Set<UUID>) -> [CompletedRecord<UUID, Ring>] {
        let shown = rows.filter { $0.deletedAt == nil && dogs.contains($0.dogID) }
        return Dictionary(grouping: shown) { RingKey(dog: $0.dogID, ring: $0.ring) }.values
            .compactMap { $0.min { ($0.completedAt, $0.id.uuidString) < ($1.completedAt, $1.id.uuidString) }?.record }
    }

    /// Keeps the earliest of the ring stamps that were stored for the same
    /// dog and ring, like `mergeRecords(of:)`. It returns whether it deleted
    /// a stamp.
    private func mergeRings(_ rings: [CompletedRing]) -> Bool {
        let groups = Dictionary(grouping: rings) { RingKey(dog: $0.dogID, ring: $0.ring) }
        return deleteAllButEarliest(groups.values, order: { ($0.completedAt, $0.id.uuidString) })
    }

    /// The area steps that are not deleted.
    private static let shownAreaSteps = FetchDescriptor<AreaStep>(predicate: #Predicate { $0.deletedAt == nil })

    /// The records of the area steps with a step that this build knows.
    private static func records(of steps: [AreaStep]) -> [CompletedRecord<UUID, AreaStepID>] {
        steps.compactMap { step in
            step.stampStep.map {
                CompletedRecord(dog: step.dogID, goal: AreaStepID(area: step.area, step: $0), date: step.reachedAt)
            }
        }
    }

    /// Keeps the earliest of the area steps that were stored for the same
    /// dog, area and step, like `mergeRecords(of:)`. It returns whether it
    /// deleted a step.
    private func mergeSteps(_ steps: [AreaStep]) -> Bool {
        let groups = Dictionary(grouping: steps) { StepKey(dog: $0.dogID, area: $0.area, step: $0.step) }
        return deleteAllButEarliest(groups.values, order: { ($0.reachedAt, $0.id.uuidString) })
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
}

/// The part of an update that runs off the main actor: it reads the map
/// packages and the stored matches, and matches the walks.
nonisolated private struct Matcher: Sendable {
    /// The history to add to, and the dogs that each walk adds to it.
    struct Plan: Sendable {
        let history: CollectionHistory
        /// The walks to add and their dogs, in the order of time, so that
        /// most walks follow the intervals that the history keeps.
        let additions: [(key: WalkMatchCache.Key, dogs: Set<UUID>)]
        /// All ended walks, whose stored matches stay.
        let walks: Set<WalkMatchCache.Key>
    }

    /// What the first step reads.
    struct Stored: Sendable {
        let cache: WalkMatchCache?
        let matches: [WalkMatchCache.Key: WalkMatch]
        /// The areas, the streets and the cantons, if the step loaded them.
        let loadedAreas: LoadedAreas?
    }

    /// The history after a rebuild, and whether every walk has a match. A
    /// walk whose track cannot be read has none.
    struct Rebuilt: Sendable {
        let history: CollectionHistory
        let matchedEveryWalk: Bool
        /// The marks of each added walk that started at the date of the
        /// rebuild or later.
        let marks: [WalkMatchCache.Key: [Segment.ID: Date]]
    }

    struct LoadedAreas: Sendable {
        let areas: [Int: Area]
        let streets: [Int: [Street]]
        let cantons: [String]
    }

    let packages: MapPackages
    let cacheRoot: URL?

    /// The identity of the map packages, of which the version of the
    /// collections follows (`CacheFolder.version(packages:)`).
    @concurrent func identity() async throws -> String {
        try packages.identity()
    }

    /// The walks that the history does not hold yet, and the history to add
    /// them to (`CollectionHistory.prepared(for:dogs:)`). Without a history
    /// of this version, the plan adds all walks to an empty one.
    @concurrent func plan(for input: CollectionInput, history: CollectionHistory?) async throws -> Plan {
        var current: [WalkMatchCache.Key: Set<UUID>] = [:]
        for walk in input.walks {
            if let key = walk.key {
                current[key, default: []].formUnion(walk.dogs.intersection(input.dogs))
            }
        }
        let prepared = (history ?? CollectionHistory()).prepared(for: current, dogs: input.dogs)
        return Plan(
            history: prepared.history,
            additions: prepared.additions.map { (key: $0.key, dogs: $0.value) }.sorted { $0.key.startedAt < $1.key.startedAt },
            walks: Set(current.keys))
    }

    /// The stored match of each walk that has one, and the areas and the
    /// streets if they are needed.
    @concurrent func stored(for keys: [WalkMatchCache.Key], loadsAreas: Bool, identity: String) async throws -> Stored {
        let cache = cacheRoot.flatMap { WalkMatchCache.forPackages(identity, in: $0) }
        var matches: [WalkMatchCache.Key: WalkMatch] = [:]
        for key in keys {
            matches[key] = cache?.match(for: key)
        }
        return Stored(cache: cache, matches: matches, loadedAreas: loadsAreas ? try loadAreas() : nil)
    }

    /// The marks of the walks whose matches are stored. A walk without a
    /// stored match has none.
    @concurrent func marks(for keys: [WalkMatchCache.Key]) async throws -> [WalkMatchCache.Key: [Segment.ID: Date]] {
        let identity = try packages.identity()
        let cache = cacheRoot.flatMap { WalkMatchCache.forPackages(identity, in: $0) }
        var marks: [WalkMatchCache.Key: [Segment.ID: Date]] = [:]
        for key in keys {
            try Task.checkCancellation()
            marks[key] = cache?.match(for: key)?.marks
        }
        return marks
    }

    /// The segments whose midpoints lie within the radius of the home base.
    @concurrent func ringSegments(around centre: HomeBase, withinMetres radius: Double) async throws -> RingSegments {
        let segments = try packages.segments(in: [RingSegments.box(around: centre, withinMetres: radius)])
        return RingSegments(centre: centre, segments: segments, radiusMetres: radius)
    }

    private func loadAreas() throws -> LoadedAreas {
        let areas = try packages.areas()
        let streets = try packages.streets()
        return LoadedAreas(
            areas: Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            streets: Dictionary(grouping: streets, by: \.id.area),
            cantons: Set(areas.map(\.canton)).sorted())
    }

    /// Adds the walks of the plan to its history. It matches the walks that
    /// have no stored match, and stores their matches.
    ///
    /// A track that cannot be read collects nothing, as it shows as empty.
    /// Neither its match nor the walk in the history is stored, so that the
    /// next update tries it again.
    ///
    /// - Parameter marksSince: The rebuild gives the marks of the added walks
    ///   that started at this date or later.
    @concurrent func collections(
        adding plan: Plan, stored: Stored, trackData: [WalkMatchCache.Key: Data?], marksSince: Date
    ) async throws -> Rebuilt {
        var matches = stored.matches
        var matchedEveryWalk = true
        if !trackData.isEmpty {
            let tracks = trackData.mapValues { data in data.flatMap { try? Track(data: $0) } }
            matchedEveryWalk = !tracks.values.contains(nil)
            let engine = try packages.engine(covering: tracks.values.compactMap { $0 })
            for (key, track) in tracks {
                try Task.checkCancellation()
                guard let track else { continue }
                let match = engine.match(track)
                matches[key] = match
                stored.cache?.store(match, for: key)
            }
        }
        var history = plan.history
        var marks: [WalkMatchCache.Key: [Segment.ID: Date]] = [:]
        for (key, dogs) in plan.additions {
            try Task.checkCancellation()
            guard let match = matches[key] else { continue }
            history.add(match, of: key, for: dogs)
            if key.startedAt >= marksSince {
                marks[key] = match.marks
            }
        }
        try Task.checkCancellation()
        stored.cache?.removeAll(except: plan.walks)
        return Rebuilt(history: history, matchedEveryWalk: matchedEveryWalk, marks: marks)
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
        let steps = stepRecords(of: dog.id)
        let key = PageKey(canton: canton, dog: dog.id, records: records, steps: steps)
        if let pages = pageCache[key] { return pages }
        let pages = CollectionBook.pages(
            canton: canton, areas: Array(areas.values), collection: collection,
            dog: dog.id, records: records, steps: steps)
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
    /// has built the collection of the dog, because the update adds the
    /// records of newly completed goals.
    func totals(of dog: Dog) -> DogTotals? {
        guard byDog[dog.id] != nil else { return nil }
        return DogTotals(
            dog: dog.id,
            areaRecords: dog.completedAreaRecords, streetRecords: dog.completedStreetRecords)
    }

    /// The number of segments that the dog collected during the walk, for
    /// the home screen, or nil until an update has built the collection of
    /// the dog with the walk. A walk that has just ended, or a walk that a
    /// dog has just joined, has no count until the next update ends.
    func collectedSegmentCount(during walk: Walk, of dog: Dog) -> Int? {
        guard let endedAt = walk.endedAt, isBuilt(walk, for: dog.id) else { return nil }
        return collection(of: dog.id).collectedSegmentCount(during: walk.startedAt...endedAt)
    }

    /// Whether the last update built the walk into the collection of the dog.
    func isBuilt(_ walk: Walk, for dog: UUID) -> Bool {
        byDog[dog] != nil && walksByDog[dog]?.contains(walk.id) == true
    }

    /// The feature IDs of the segments that the walk collected for at least
    /// one of its dogs, for the map of the walk. It is empty until an update
    /// has built the collections with the walk.
    func collectedFeatures(during walk: Walk) -> Set<Int> {
        guard let endedAt = walk.endedAt else { return [] }
        var features: Set<Int> = []
        for dog in walk.dogs where isBuilt(walk, for: dog.id) {
            features.formUnion(collection(of: dog.id).collectedFeatures(during: walk.startedAt...endedAt))
        }
        return features
    }

    /// The pages of the pinned areas for the dog, for the home screen.
    func pinnedPages(_ pinned: [Area.ID], for dog: Dog) -> [CollectionBook.Page] {
        CollectionBook.pinnedPages(
            pinned: pinned, areas: Array(areas.values), collection: collection(of: dog.id),
            dog: dog.id, records: dog.completedAreaRecords, steps: stepRecords(of: dog.id))
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

/// Updates the collections whenever the dogs, the ended walks, their dogs,
/// the completed records, the area steps, the ring stamps or the home base
/// change. The app starts the first update at launch.
struct CollectionUpdates: ViewModifier {
    @Environment(Collections.self) private var collections
    @Query(Dog.all()) private var dogs: [Dog]
    /// A walk counts when it has ended. During a walk, `CurrentWalk` matches its points.
    @Query(Walk.ended()) private var walks: [Walk]
    /// The update merges two records of the same dog and goal.
    @Query private var completedAreas: [CompletedArea]
    @Query private var completedStreets: [CompletedStreet]
    @Query private var areaSteps: [AreaStep]
    @Query private var completedRings: [CompletedRing]
    @Query(Pack.all()) private var packs: [Pack]

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
            recordCount: completedAreas.count + completedStreets.count + areaSteps.count + completedRings.count,
            homeBase: packs.first?.homeBase)
    }
}

private struct PageKey: Hashable {
    let canton: String
    let dog: UUID
    let records: [CompletedRecord<UUID, Area.ID>]
    let steps: [CompletedRecord<UUID, AreaStepID>]
}

/// The area steps of one dog, area and step, of which only one stays.
private struct StepKey: Hashable {
    let dog: UUID
    let area: Area.ID
    let step: Int
}

private struct UpdateInput: Equatable {
    let collections: CollectionInput
    let recordCount: Int
    let homeBase: HomeBase?
}

/// The ring stamps of one dog and ring, of which only one stays.
private struct RingKey: Hashable {
    let dog: UUID
    let ring: Ring
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
            WalkInput(walk: $0.id, key: WalkMatchCache.Key($0), dogs: Set($0.dogs.map(\.id)))
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
                lengthMetres: segment.lengthMetres, collectedAt: collectedAt,
                markedAt: segment.markedAt ?? collectedAt)
        }
    }
}

extension WalkedSegment {
    /// Gives the row the history of its segment, and the covered parts and
    /// the collected segment that follow from it. It writes only the values
    /// that changed, so that an unchanged row is not saved.
    fileprivate func update(_ entry: CoverageHistory.Entry) {
        set(\.coveredParts, to: entry.parts.data)
        set(\.collectedAt, to: entry.collected?.collectedAt)
        set(\.markedAt, to: entry.collected?.markedAt)
        set(\.fid, to: entry.segment.fid)
        set(\.area, to: entry.segment.area)
        set(\.streetName, to: entry.segment.street?.name)
        set(\.lengthMetres, to: entry.segment.lengthMetres)
        set(\.planeLengthMetres, to: entry.segment.planeLengthMetres)
        set(\.keptIntervals, to: entry.covered.data)
        set(\.walkMarkedAt, to: entry.markedAt)
    }

    /// The history of the segment as the row keeps it.
    fileprivate var historyEntry: CoverageHistory.Entry {
        CoverageHistory.Entry(
            segment: MatchedSegment(
                fid: fid, area: area, street: streetName.map { Street.ID(area: area, name: $0) },
                lengthMetres: lengthMetres, planeLengthMetres: planeLengthMetres),
            covered: [CoveredInterval](data: keptIntervals), markedAt: walkMarkedAt)
    }
}
