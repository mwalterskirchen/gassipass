//
//  CurrentWalk.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import CoreLocation
import Foundation
import Observation
import OSLog
import SwiftData

/// The current walk: the walk that the app records now, with its live
/// feedback.
///
/// It records the raw GPS points of the location source, also in the
/// background and without a mobile network, and saves the track while it
/// records. When the system terminates the app during a walk, Core Location
/// launches the app again, and the current walk continues the unfinished
/// walk of the store.
///
/// The live feedback is the new segments near the walker for at least one dog
/// on the walk, a vibration when a segment becomes collected for any dog on
/// the walk unless the user switched it off in the settings, the live
/// completion of the current area for each dog, the segments collected on the
/// walk, the current ring and the collected segments with their marks for the
/// map, and the stamps that the dogs earn on the walk: the completed streets,
/// the entry stamps, the steps and the full stamps of areas, the ring
/// stamps, and the weekly goals and week stamps that the walk finishes. The
/// live mode of the collection engine applies the rules. A stopped walk
/// stays as the ended walk until the member closes its summary.
///
/// The current walk handles one event at a time: a GPS point, a change of
/// the location status, or new collections. The map packages and the replay
/// of the track after a relaunch run off the main actor, and the next event
/// waits for them.
@Observable
final class CurrentWalk {
    enum LocationStatus: Equatable {
        case waiting
        case recording(accuracyMetres: Double)
        case unavailable
        case denied
    }

    /// The live completion of one dog on the walk.
    struct DogCompletion: Identifiable {
        let id: UUID
        let dogName: String
        let completion: Completion
    }

    /// A stamp that dogs on the walk earned during the walk: a completed
    /// street, a step of the stamp of an area, a ring stamp, or a finished
    /// weekly goal.
    struct CompletedGoal: Identifiable, Equatable {
        enum ID: Hashable {
            /// The step of the stamp of the area. `.completed` is the full
            /// stamp of a completed area.
            case area(Area.ID, StampStep)
            case street(Street.ID)
            case ring(Ring)
            case weeklyGoal(WeeklyGoal)
            /// The week stamp of the week that starts at the date.
            case weekStamp(Date)
        }

        let id: ID
        /// The name of the street, the area, the ring or the week, or the
        /// weekly goal in words.
        let name: String
        /// The BFS number of the area, or of the area that the street lies
        /// in, or nil for a ring, a weekly goal or a week stamp.
        let area: Area.ID?
        /// The names of the dogs that earned it, sorted.
        let dogNames: [String]
        let date: Date
    }

    /// How often the current walk saves the track.
    nonisolated static let saveInterval: TimeInterval = 30
    /// The map shows the new segments within this distance of the walker.
    nonisolated static let nearRadiusMetres = 500.0
    /// The engine holds the segments within this distance of the point where
    /// they were loaded. When the walker comes near the edge of that box, the
    /// current walk loads the segments around the walker again.
    nonisolated static let loadRadiusMetres = 1500.0

    /// The time without movement in words, for example "1 hour".
    static var timeWithoutMovementText: String {
        Duration.seconds(StillnessCheck.timeWithoutMovement)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    /// The walk that is being recorded, if any.
    private(set) var walk: Walk?
    /// The walk that has just stopped, until the member closes its summary,
    /// or nil when the walk has left the store, for example with its pack.
    var endedWalk: Walk? {
        stoppedWalk.flatMap { $0.isInStore ? $0 : nil }
    }
    /// The walk that has just stopped, until the member closes its summary.
    private var stoppedWalk: Walk?
    /// The distance of the walk so far, in metres.
    var distanceMetres: Double {
        distance.metres
    }
    private(set) var locationStatus = LocationStatus.waiting
    /// The time at which the app asks whether the walk has ended.
    private(set) var askAt: Date?

    /// The segments near the walker that are new for at least one dog on the walk.
    private(set) var newSegments: [Segment] = []
    /// The area that the walker is in, or nil before it is known.
    private(set) var currentArea: Area?
    /// The live completion of the current area for each dog on the walk, sorted by name.
    private(set) var completions: [DogCompletion] = []
    /// The segments that became collected on this walk for at least one dog on the walk.
    private(set) var collectedOnWalk: Set<Segment.ID> = []
    /// The stamps that dogs on the walk earned during the walk, in order.
    /// After a relaunch it starts empty again.
    private(set) var completedOnWalk: [CompletedGoal] = []
    /// The smallest current ring of the dogs on the walk, or nil without a
    /// home base or before the live walk starts.
    private(set) var currentRing: Ring?
    /// The segments that every dog on the walk has collected, also on this
    /// walk, by the age of their marks, for the map.
    private(set) var markedFeatures = MarkedFeatures()
    private var hasLiveWalk = false

    /// Whether the live feedback knows the collections of all dogs on the
    /// walk and the areas. Until then it shows no area and no completion.
    var isReady: Bool {
        hasLiveWalk && !collections.areas.isEmpty
    }

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let collections: Collections
    @ObservationIgnored private let packages: MapPackages
    @ObservationIgnored private let location: any LocationSource
    @ObservationIgnored private let signals: any WalkSignals
    @ObservationIgnored private let settings: AppSettings
    /// The ID of this device, which each new walk stores.
    @ObservationIgnored private let deviceID: String
    /// The name of the member on this phone, which each new walk stores.
    @ObservationIgnored private let memberName: () -> String
    @ObservationIgnored private let now: () -> Date

    private static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "CurrentWalk")

    @ObservationIgnored private var track = Track()
    private var distance = WalkDistance()
    @ObservationIgnored private var stillness: StillnessCheck?
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var dogNames: [UUID: String] = [:]
    /// The live walk, or nil until the collections of all dogs on the walk
    /// are known. Until then the feedback shows nothing, so that it does not
    /// report segments that the dogs have already collected.
    @ObservationIgnored private var live: CollectionEngine.LiveWalk<UUID>?
    /// The collections of the dogs from their ended walks, that the live walk started on.
    @ObservationIgnored private var collectionsBeforeWalk: [UUID: DogCollection] = [:]
    /// The ring stamps that the dogs earned on this walk, which the
    /// collections store only after the walk.
    @ObservationIgnored private var ringsOnWalk: [CompletedRecord<UUID, Ring>] = []
    /// The weekly goals of the dogs on the walk, or nil until the live walk
    /// starts.
    @ObservationIgnored private var liveGoals: LiveGoals?
    /// The collected segments whose marks this walk refreshed, for each dog,
    /// with the time of each mark, for the weekly goals.
    @ObservationIgnored private var marksOnWalk: [UUID: [Segment.ID: Date]] = [:]
    /// The stamps that the dogs earned on this walk, for the weekly goals.
    @ObservationIgnored private var recordsOnWalk: [UUID: GoalRecords] = [:]
    @ObservationIgnored private var engine = CollectionEngine(segments: [])
    @ObservationIgnored private var loadedBox: CoordinateBox?
    /// The tasks that deliver and handle the events of the walk.
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    /// It continues an unfinished walk at once, also when Core Location
    /// launches the app in the background.
    init(
        context: ModelContext, collections: Collections, packages: MapPackages,
        location: any LocationSource = CoreLocationSource(), signals: any WalkSignals = SystemWalkSignals(),
        settings: AppSettings, deviceID: String = ThisDevice.id, memberName: @escaping () -> String = { "" },
        now: @escaping () -> Date = { .now }
    ) {
        self.context = context
        self.collections = collections
        self.packages = packages
        self.location = location
        self.signals = signals
        self.settings = settings
        self.deviceID = deviceID
        self.memberName = memberName
        self.now = now
        guard let walk = try? context.fetch(Walk.unfinished()).first else { return }
        do {
            record(walk, track: try walk.readTrack())
        } catch {
            // Recording on would replace the stored points (ADR 0002). End
            // the walk instead and keep its stored track as it is.
            walk.endedAt = now()
            walk.noteChange(at: now())
            save()
        }
    }

    func start(dogs: [Dog]) {
        precondition(!dogs.isEmpty, "A walk has at least one dog.")
        guard walk == nil else { return }
        stoppedWalk = nil
        let walk = Walk(startedAt: now(), dogs: dogs, context: context)
        walk.deviceID = deviceID
        // Without an account the name is empty, which means the pack owner,
        // because without an account this person is the pack owner.
        walk.memberName = memberName()
        save()
        signals.prepare()
        record(walk, track: Track())
    }

    func stop() {
        guard let walk else { return }
        tasks.forEach { $0.cancel() }
        tasks = []
        signals.stopAsking()

        walk.store(track, distanceMetres: distanceMetres)
        walk.endedAt = now()
        walk.noteChange(at: now())
        save()

        stoppedWalk = walk
        self.walk = nil
        track = Track()
        distance = WalkDistance()
        locationStatus = .waiting
        stillness = nil
        askAt = nil
        lastSave = .distantPast
        dogNames = [:]
        live = nil
        hasLiveWalk = false
        collectionsBeforeWalk = [:]
        ringsOnWalk = []
        liveGoals = nil
        marksOnWalk = [:]
        recordsOnWalk = [:]
        engine = CollectionEngine(segments: [])
        loadedBox = nil
        newSegments = []
        currentArea = nil
        completions = []
        collectedOnWalk = []
        completedOnWalk = []
        currentRing = nil
        markedFeatures = MarkedFeatures()
    }

    /// The member closes the summary of the ended walk.
    func closeSummary() {
        stoppedWalk = nil
    }

    /// Saves the store. A failed save is logged, and the changes stay in the
    /// context for the next save.
    private func save() {
        do {
            try context.save()
        } catch {
            Self.logger.error("The walk cannot save: \(String(describing: error), privacy: .public)")
        }
    }

    /// The walker answers that the walk has not ended yet. The walk keeps
    /// the answer, so that it counts also after a relaunch.
    func continueWalk() {
        let date = now()
        stillness?.walkContinues(at: date)
        walk?.continuedAt = date
        walk?.noteChange(at: date)
        save()
        showAskAt()
    }

    private func record(_ walk: Walk, track: Track) {
        self.walk = walk
        self.track = track
        distance = WalkDistance(track)
        var stillness = StillnessCheck(startedAt: walk.startedAt)
        track.points.forEach { stillness.add($0) }
        if let continuedAt = walk.continuedAt {
            stillness.walkContinues(at: continuedAt)
        }
        self.stillness = stillness
        showAskAt()
        let dogs = walk.dogs
        dogNames = Dictionary(dogs.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        // One queue of events, so that the walk handles them one at a time.
        let (events, queue) = AsyncStream<Event>.makeStream()
        let locationEvents = location.start()
        let dogIDs = Set(dogNames.keys)
        tasks = [
            Task {
                for await event in locationEvents {
                    queue.yield(.location(event))
                }
            },
            // The collections change when the first update after the start of
            // the app ends. The live walk then starts again on the new collections.
            Task { [collections] in
                for await byDog in Observations({ collections.byDog }) {
                    queue.yield(.collections(byDog.filter { dogIDs.contains($0.key) }))
                }
            },
            Task { [weak self] in
                for await event in events {
                    guard let self, !Task.isCancelled else { return }
                    await self.handle(event)
                }
            },
        ]
    }

    private enum Event {
        case location(LocationEvent)
        case collections([UUID: DogCollection])
    }

    private func handle(_ event: Event) async {
        switch event {
        case .location(.point(let point)):
            await add(point)
        case .location(.denied):
            locationStatus = .denied
        case .location(.unavailable):
            locationStatus = .unavailable
        case .collections(let byDog):
            await startLiveWalk(on: byDog)
        }
    }

    private func add(_ point: TrackPoint) async {
        distance.add(point)
        track.points.append(point)
        locationStatus = .recording(accuracyMetres: point.horizontalAccuracy)
        let askedAt = stillness?.askAt
        stillness?.add(point)
        if stillness?.askAt != askedAt {
            showAskAt()
        }
        if let walk, now().timeIntervalSince(lastSave) >= Self.saveInterval {
            walk.store(track, distanceMetres: distanceMetres)
            walk.noteChange(at: now())
            save()
            lastSave = now()
        }

        guard live != nil else { return }
        await loadSegments(around: point)
        guard !Task.isCancelled, var live else { return }
        let change = live.add(point, using: engine)
        let newlyCollected = change.collected
        self.live = live
        if !change.refreshed.isEmpty {
            // A refreshed mark gives no vibration, so that the usual round
            // does not vibrate at every corner.
            showMarks(of: live)
            for (dog, segments) in change.refreshed {
                for segment in segments {
                    marksOnWalk[dog, default: [:]][segment] = point.timestamp
                }
            }
        }
        if !newlyCollected.isEmpty {
            if settings.vibratesForCollectedSegments {
                signals.vibrate()
            }
            collectedOnWalk.formUnion(newlyCollected.values.joined())
            addCompleted(by: newlyCollected, at: point.timestamp, in: live.collections)
            addCompletedRings(by: newlyCollected, at: point.timestamp, in: live.collections)
            showRings(of: live)
        }
        addFinishedGoals(of: live, at: point.timestamp)
        showFeedback(at: point)
    }

    /// Adds the weekly goals that the walk finished with the point, and the
    /// week stamps of the dogs that finished their last goal. Of the dogs
    /// with the same goal, it shows the goal once.
    private func addFinishedGoals(of live: CollectionEngine.LiveWalk<UUID>, at date: Date) {
        guard var liveGoals else { return }
        let finished = liveGoals.finishedGoals(
            collections: live.collections, marks: marksOnWalk, records: recordsOnWalk,
            distanceMetres: distanceMetres, at: date)
        self.liveGoals = liveGoals
        guard !finished.isEmpty else { return }
        let dogs = (walk?.dogs ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var shown: [WeeklyGoal] = []
        for goal in finished.map(\.goal) where !shown.contains(goal) {
            shown.append(goal)
            let dogIDs = Set(finished.filter { $0.goal == goal }.map(\.dog))
            completedOnWalk.append(CompletedGoal(
                id: .weeklyGoal(goal), name: collections.title(of: goal), area: nil,
                dogNames: dogs.filter { dogIDs.contains($0.id) }.map(\.name), date: date))
        }
        let stamped = Set(finished.filter(\.givesWeekStamp).map(\.dog))
        if let walk, !stamped.isEmpty {
            let weekStart = WeekCalendar.week(containing: walk.startedAt).start
            completedOnWalk.append(CompletedGoal(
                id: .weekStamp(weekStart), name: GoalText.weekName(of: weekStart), area: nil,
                dogNames: dogs.filter { stamped.contains($0.id) }.map(\.name), date: date))
        }
    }

    /// Starts the weekly goals of the dogs on the walk, from their sets of
    /// the week of the walk and their ended walks.
    private func startLiveGoals(before collections: [UUID: DogCollection]) {
        guard let walk else { return }
        let endedWalks = (try? context.fetch(Walk.ended())) ?? []
        let dogs = walk.dogs.compactMap { dog -> LiveGoals.Dog? in
            guard let set = self.collections.goalSet(of: dog.id, at: walk.startedAt) else { return nil }
            return LiveGoals.Dog(
                id: dog.id, set: set, walks: self.collections.goalWalks(of: dog.id, in: endedWalks),
                records: self.collections.goalRecords(of: dog))
        }
        liveGoals = LiveGoals(dogs: dogs, walkID: walk.id, startedAt: walk.startedAt, collections: collections)
    }

    /// Adds the streets that the newly collected segments completed, and
    /// then the stamps of the areas. A dog that already has the record of a
    /// stamp, for example before a map release reopened the area, does not
    /// earn it again. The stamp of an area grows in one place, so each area
    /// shows only its highest new step, with the dogs that reached it.
    private func addCompleted(
        by newlyCollected: [UUID: Set<Segment.ID>], at date: Date,
        in byDog: [UUID: DogCollection]
    ) {
        let dogs = (walk?.dogs ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let streets: [Street.ID: Set<UUID>] = CollectionEngine.completedGoals(
            by: newlyCollected, in: byDog) { [collections] id in collections.streets[id.area]?.first { $0.id == id } }
        for (street, dogIDs) in streets.sorted(by: { $0.key.name < $1.key.name }) {
            let earned = dogs.filter { dogIDs.contains($0.id) && !$0.completedStreetRecords.contains { $0.goal == street } }
            for dog in earned {
                recordsOnWalk[dog.id, default: GoalRecords()].streets.append(
                    CompletedRecord(dog: dog.id, goal: street, date: date))
            }
            let names = earned.map(\.name)
            guard !names.isEmpty else { continue }
            completedOnWalk.append(CompletedGoal(
                id: .street(street), name: street.name, area: street.area, dogNames: names, date: date))
        }

        let reached = CollectionEngine.reachedSteps(
            by: newlyCollected, in: byDog) { [collections] in collections.areas[$0] }
        var newSteps: [Area.ID: [UUID: StampStep]] = [:]
        for (id, dogIDs) in reached {
            for dog in dogs where dogIDs.contains(dog.id) && !hasRecord(of: id, for: dog) {
                newSteps[id.area, default: [:]][dog.id] = max(newSteps[id.area]?[dog.id] ?? id.step, id.step)
                recordsOnWalk[dog.id, default: GoalRecords()].steps.append(
                    CompletedRecord(dog: dog.id, goal: id, date: date))
            }
        }
        for (area, stepByDog) in newSteps.sorted(by: { $0.key < $1.key }) {
            guard let step = stepByDog.values.max(), let name = collections.areas[area]?.name else { continue }
            let names = dogs.filter { stepByDog[$0.id] == step }.map(\.name)
            completedOnWalk.append(CompletedGoal(
                id: .area(area, step), name: name, area: area, dogNames: names, date: date))
        }
    }

    /// Adds the rings that the newly collected segments completed. A dog
    /// that already has the ring stamp does not earn it again.
    private func addCompletedRings(
        by newlyCollected: [UUID: Set<Segment.ID>], at date: Date, in byDog: [UUID: DogCollection]
    ) {
        guard let rings = collections.ringSegments, rings.centre == collections.homeBase else { return }
        let dogs = (walk?.dogs ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let completed = CollectionEngine.completedRings(by: newlyCollected, in: byDog, around: rings)
        for (ring, dogIDs) in completed.sorted(by: { $0.key.number < $1.key.number }) {
            let earned = dogs.filter { dog in
                dogIDs.contains(dog.id) && !collections.ringRecords.contains { $0.dog == dog.id && $0.goal == ring }
            }
            guard !earned.isEmpty else { continue }
            ringsOnWalk += earned.map { CompletedRecord(dog: $0.id, goal: ring, date: date) }
            for dog in earned {
                recordsOnWalk[dog.id, default: GoalRecords()].rings.append(
                    CompletedRecord(dog: dog.id, goal: ring, date: date))
            }
            completedOnWalk.append(CompletedGoal(
                id: .ring(ring), name: ring.name, area: nil, dogNames: earned.map(\.name), date: date))
        }
    }

    /// Shows the smallest current ring of the dogs on the walk, and the
    /// segments that every dog has collected with their marks.
    private func showRings(of live: CollectionEngine.LiveWalk<UUID>) {
        let records = collections.ringRecords + ringsOnWalk
        currentRing = collections.homeBase.flatMap { home in
            live.dogs
                .map {
                    CollectionEngine.currentRing(
                        of: $0, around: home, records: records, skippingEmptyIn: collections.ringSegments)
                }
                .min { $0.number < $1.number }
        }
        showMarks(of: live)
    }

    /// Shows the segments that every dog on the walk has collected, by the
    /// age of their marks.
    private func showMarks(of live: CollectionEngine.LiveWalk<UUID>) {
        let marks = MarkedFeatures(collections: Array(live.collections.values), at: now())
        if marks != markedFeatures {
            markedFeatures = marks
        }
    }

    /// Whether the dog has the record of the step of the area stamp.
    private func hasRecord(of step: AreaStepID, for dog: Dog) -> Bool {
        if step.step == .completed {
            dog.completedAreaRecords.contains { $0.goal == step.area }
        } else {
            collections.stepRecords(of: dog.id).contains { $0.goal == step }
        }
    }

    private func showAskAt() {
        askAt = stillness?.askAt
        if let askAt {
            signals.ask(at: askAt)
        }
    }

    /// Starts the live walk on the collections of the dogs and adds the
    /// points so far, without a vibration.
    private func startLiveWalk(on byDog: [UUID: DogCollection]) async {
        guard byDog.count == dogNames.count, byDog != collectionsBeforeWalk || live == nil else { return }
        collectionsBeforeWalk = byDog
        startLiveGoals(before: byDog)
        let start = CollectionEngine.LiveWalk(dogs: Set(dogNames.keys), collections: byDog)
        guard let last = track.points.last else {
            live = start
            hasLiveWalk = true
            showRings(of: start)
            return
        }
        let replay = await Self.replay(track, on: start, packages: packages, engine: engine)
        guard !Task.isCancelled else { return }
        if let loaded = replay.loadedEngine {
            engine = loaded
            loadedBox = CollectionEngine.box(around: last.coordinate, withinMetres: Self.loadRadiusMetres)
        }
        live = replay.live
        hasLiveWalk = true
        collectedOnWalk = replay.collected
        // The goals that the replayed points finished do not show again. The
        // replay does not know the marks and the stamps of the walk, so they
        // count only when the walk ends.
        _ = liveGoals?.finishedGoals(
            collections: replay.live.collections, marks: [:], records: [:], distanceMetres: distanceMetres,
            at: last.timestamp)
        showRings(of: replay.live)
        showFeedback(at: last)
    }

    /// The live walk after all points of the track, with an engine for the
    /// whole track and the area around the walker. If the packages cannot
    /// be read, it uses the engine that it has, and the next point tries again.
    @concurrent nonisolated private static func replay(
        _ track: Track, on live: CollectionEngine.LiveWalk<UUID>, packages: MapPackages,
        engine: CollectionEngine
    ) async -> Replay {
        let last = track.points.last?.coordinate ?? CLLocationCoordinate2D()
        let loaded = try? packages.engine(around: last, withinMetres: loadRadiusMetres, covering: track)
        var live = live
        var collected: Set<Segment.ID> = []
        for point in track.points {
            collected.formUnion(live.add(point, using: loaded ?? engine).collected.values.joined())
        }
        return Replay(loadedEngine: loaded, live: live, collected: collected)
    }

    nonisolated private struct Replay: Sendable {
        let loadedEngine: CollectionEngine?
        let live: CollectionEngine.LiveWalk<UUID>
        let collected: Set<Segment.ID>
    }

    /// Makes sure that the engine holds every segment near the point. If
    /// the packages cannot be read, the engine stays as it is, and the next
    /// point tries again.
    private func loadSegments(around point: TrackPoint) async {
        let needed = CollectionEngine.box(around: point.coordinate, withinMetres: Self.nearRadiusMetres)
        if let loadedBox, loadedBox.contains(needed) { return }
        guard let loaded = try? await Self.engine(around: point.coordinate, from: packages), !Task.isCancelled
        else { return }
        engine = loaded
        loadedBox = CollectionEngine.box(around: point.coordinate, withinMetres: Self.loadRadiusMetres)
    }

    @concurrent nonisolated private static func engine(
        around point: CLLocationCoordinate2D, from packages: MapPackages
    ) async throws -> CollectionEngine {
        try packages.engine(around: point, withinMetres: loadRadiusMetres)
    }

    /// Shows the new segments near the point and the live completion of the
    /// current area for each dog.
    private func showFeedback(at point: TrackPoint) {
        guard let live else { return }
        let near = engine.newSegments(
            near: point.coordinate, withinMetres: Self.nearRadiusMetres, for: live.dogs, in: live.collections)
        if near.map(\.id).sorted() != newSegments.map(\.id).sorted() {
            newSegments = near
        }
        currentArea = live.currentArea.flatMap { collections.areas[$0] }
        completions = currentArea.map { area in
            live.collections
                .map { DogCompletion(id: $0.key, dogName: dogNames[$0.key] ?? "", completion: $0.value.completion(of: area)) }
                .sorted { $0.dogName.localizedStandardCompare($1.dogName) == .orderedAscending }
        } ?? []
    }
}

extension CurrentWalk {
    /// A current walk with an empty store and no map packages, for previews.
    static func preview() -> CurrentWalk {
        CurrentWalk(
            context: .preview, collections: .preview(), packages: MapPackages(urls: []), settings: AppSettings())
    }
}
