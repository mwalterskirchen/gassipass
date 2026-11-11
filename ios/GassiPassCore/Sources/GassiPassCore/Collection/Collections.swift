//
//  Collections.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import OSLog
import SwiftData

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
public final class Collections {
    /// The collection of each dog, from the store or else empty until the
    /// first update.
    public internal(set) var byDog: [UUID: DogCollection] = [:]
    /// The ended walks of each dog that its collection is built from, from
    /// the store or else empty until the first update.
    var walksByDog: [UUID: Set<UUID>] = [:]
    /// The areas of all packages by BFS number, empty until they are loaded.
    public private(set) var areas: [Int: Area] = [:]
    /// The streets of all packages by the BFS number of their area, empty
    /// until they are loaded.
    public private(set) var streets: [Int: [Street]] = [:]
    /// The cantons of all packages, sorted, empty until the areas are loaded.
    public private(set) var cantons: [String] = []
    /// The area steps of all dogs from the store, which are not deleted.
    public internal(set) var stepRecords: [CompletedRecord<UUID, AreaStepID>] = []
    /// The ring stamps of all dogs from the store, which are not deleted.
    public internal(set) var ringRecords: [CompletedRecord<UUID, Ring>] = []
    /// The home base of the pack at the last update, or nil.
    public internal(set) var homeBase: HomeBase?
    /// The segments around the home base that the rings of the last update
    /// needed, or nil until they are loaded. They hold the current ring of
    /// each dog and the ring after it, so that the map has new segments
    /// beyond the current ring, and a walk that completes the current ring
    /// has the next one.
    public internal(set) var ringSegments: RingSegments?
    /// The number of new stamps that each dog got from its earlier walks,
    /// at the first update after the app got the area steps, or nil when
    /// there is nothing to show. A dog with no new stamp has no entry.
    public private(set) var earlierStamps: [UUID: Int]?
    /// The sets of weekly goals of all dogs from the store, which are not
    /// deleted, as the last update left them.
    public var goalSets: [WeeklyGoalSet] = []

    /// The pages that the passport has built, by canton, dog and
    /// records. A new load of the areas or a new collection empties it.
    @ObservationIgnored var pageCache: [PageKey: [Passport.Page]] = [:]
    /// The canton where each dog has collected the most segments, for the
    /// passport. A new load of the areas or a new collection empties it.
    @ObservationIgnored var cantonCache: [UUID?: String?] = [:]

    @ObservationIgnored public let context: ModelContext
    @ObservationIgnored let matcher: Matcher
    /// The clock of the weekly goals.
    @ObservationIgnored public let now: () -> Date
    /// The notifications of the weekly goals, or nil to schedule none.
    @ObservationIgnored public let reminders: GoalReminders?
    /// The segments that each recent ended walk alone marked
    /// (`WalkMatch.Entry.markedAt`), for the weekly goals. It holds the walks
    /// that started at most `goalWeeks` weeks before the current week.
    @ObservationIgnored public var walkMarks: [WalkMatchCache.Key: [Segment.ID: Date]] = [:]
    /// The times of the marks of the recent ended walks of each dog, by
    /// segment, from `walkMarks`, for the marks on the maps.
    public private(set) var recentMarks: [UUID: [Segment.ID: [Date]]] = [:]
    /// Whether an update has built the collections and loaded the areas, so
    /// that the app can make the weekly goals.
    @ObservationIgnored public private(set) var hasUpdated = false
    /// Whether the app has asked for the weekly goals of the current week,
    /// and the next update that ends makes them (`makeWeeklyGoals()`).
    @ObservationIgnored public var areGoalSetsDue = false
    /// The user defaults that note that the stamps from earlier walks were
    /// counted, or nil to count none.
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var areasAreLoaded = false
    /// The update that runs now. A new update cancels it.
    @ObservationIgnored private var running: Task<Void, Never>?
    /// The history of the collections and its version, from the store or
    /// the last update, or nil if neither has one.
    @ObservationIgnored var history: (version: String, history: CollectionHistory)?
    /// The version and the input of the collections in the store, and
    /// whether every walk had a match, or nil if the store has none.
    @ObservationIgnored var storedBuild: (version: String, input: CollectionInput, matchedEveryWalk: Bool)?
    /// The history of each dog as the rows of the store have it, so that a
    /// store writes only the rows that changed since. It is nil when the
    /// store can differ from it, for example after a failed store or in a
    /// store from before the history, and the next store then writes every
    /// row.
    @ObservationIgnored var storedHistories: [UUID: CoverageHistory]?

    static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "Collections")
    /// Marks the load and the store of the collections, for Instruments.
    static let signposter = OSSignposter(logger: logger)

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
    public init(
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

    public func collection(of dog: UUID?) -> DogCollection {
        dog.flatMap { byDog[$0] } ?? DogCollection()
    }

    /// The area steps of the dog.
    public func stepRecords(of dog: UUID) -> [CompletedRecord<UUID, AreaStepID>] {
        stepRecords.filter { $0.dog == dog }
    }

    /// The ring stamps of the dog, around any home base.
    public func ringRecords(of dog: UUID) -> [CompletedRecord<UUID, Ring>] {
        ringRecords.filter { $0.dog == dog }
    }

    /// The current ring of the dog around the home base, or nil without a
    /// home base.
    public func currentRing(of dog: UUID) -> Ring? {
        homeBase.map {
            CollectionEngine.currentRing(of: dog, around: $0, records: ringRecords, skippingEmptyIn: ringSegments)
        }
    }

    /// The current ring of the dog with its completion and the nearest new
    /// segments, for the ring card, or nil without a home base and until an
    /// update has loaded the segments of the ring.
    public func ringStatus(of dog: UUID) -> RingStatus? {
        guard let ring = currentRing(of: dog), let ringSegments, ringSegments.holds(ring) else { return nil }
        let collection = collection(of: dog)
        return RingStatus(
            ring: ring, completion: ringSegments.completion(of: ring, for: collection),
            nearestNewSegments: ringSegments.nearestNewSegments(
                for: collection, count: RingStatus.nearestNewSegmentCount))
    }

    /// Notes that the app has shown the stamps from earlier walks.
    public func noteEarlierStampsShown() {
        earlierStamps = nil
        defaults?.removeObject(forKey: Self.earlierStampsToShowKey)
    }

    /// Brings the areas, the collections and the completed records up to
    /// date with the store.
    ///
    /// A newer update cancels this one, which then changes nothing more. An
    /// update that cannot read a map package keeps the previous collections
    /// and stores nothing, and the next update tries again.
    public func update() async {
        running?.cancel()
        let update = Task { await run() }
        running = update
        await update.value
    }

    /// Waits for the update that runs now, if any.
    public func waitForUpdate() async {
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
        let marks = Self.marksByDog(of: walks, walkMarks: walkMarks)
        if marks != recentMarks {
            recentMarks = marks
        }
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
    public func storedMarks(of walks: [Walk]) async throws -> [WalkMatchCache.Key: [Segment.ID: Date]] {
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

    /// The times of the marks of the walks of each dog, by segment.
    private static func marksByDog(
        of walks: [Walk], walkMarks: [WalkMatchCache.Key: [Segment.ID: Date]]
    ) -> [UUID: [Segment.ID: [Date]]] {
        var byDog: [UUID: [Segment.ID: [Date]]] = [:]
        for walk in walks {
            guard let key = WalkMatchCache.Key(walk), let marks = walkMarks[key] else { continue }
            for dog in walk.dogs {
                for (segment, date) in marks {
                    byDog[dog.id, default: [:]][segment, default: []].append(date)
                }
            }
        }
        return byDog
    }

    /// The marks on a map of the segments that the dog has collected, or of
    /// none without a dog.
    public func markedFeatures(of dog: UUID?, at now: Date = .now) -> MarkedFeatures {
        guard let dog else { return MarkedFeatures() }
        return MarkedFeatures(dogs: [(collection(of: dog), recentMarks[dog] ?? [:])], at: now)
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

    private func emptyCaches() {
        pageCache = [:]
        cantonCache = [:]
    }
}
