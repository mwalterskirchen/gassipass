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
/// The live feedback is the new segments near the walker for at least one
/// dog on the walk, a vibration when a segment becomes collected for any
/// dog on the walk, the live completion of the current area for each dog,
/// and the segments collected on the walk. The live mode of the collection
/// engine applies the rules.
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
        let id: PersistentIdentifier
        let dogName: String
        let completion: Completion
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
    /// The length of the track so far, in metres.
    private(set) var distanceMetres: Double = 0
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
    @ObservationIgnored private let now: () -> Date

    private static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "CurrentWalk")

    @ObservationIgnored private var track = Track()
    @ObservationIgnored private var stillness: StillnessCheck?
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var dogNames: [PersistentIdentifier: String] = [:]
    /// The live walk, or nil until the collections of all dogs on the walk
    /// are known. Until then the feedback shows nothing, so that it does not
    /// report segments that the dogs have already collected.
    @ObservationIgnored private var live: CollectionEngine.LiveWalk<PersistentIdentifier>?
    /// The collections of the dogs from their ended walks, that the live walk started on.
    @ObservationIgnored private var collectionsBeforeWalk: [PersistentIdentifier: DogCollection] = [:]
    @ObservationIgnored private var engine = CollectionEngine(segments: [])
    @ObservationIgnored private var loadedBox: CoordinateBox?
    /// The tasks that deliver and handle the events of the walk.
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    /// It continues an unfinished walk of the store at once, also when Core
    /// Location launches the app in the background.
    init(
        context: ModelContext, collections: Collections, packages: MapPackages,
        location: any LocationSource = CoreLocationSource(), signals: any WalkSignals = SystemWalkSignals(),
        now: @escaping () -> Date = { .now }
    ) {
        self.context = context
        self.collections = collections
        self.packages = packages
        self.location = location
        self.signals = signals
        self.now = now
        let unfinished = FetchDescriptor<Walk>(predicate: #Predicate { $0.endedAt == nil })
        guard let walk = try? context.fetch(unfinished).first else { return }
        do {
            record(walk, track: try walk.readTrack())
        } catch {
            // Recording on would replace the stored points (ADR 0002). End
            // the walk instead and keep its stored track as it is.
            walk.endedAt = now()
            save()
        }
    }

    func start(dogs: [Dog]) {
        precondition(!dogs.isEmpty, "A walk has at least one dog.")
        guard walk == nil else { return }
        let walk = Walk(startedAt: now(), dogs: dogs)
        context.insert(walk)
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
        save()

        self.walk = nil
        track = Track()
        distanceMetres = 0
        locationStatus = .waiting
        stillness = nil
        askAt = nil
        lastSave = .distantPast
        dogNames = [:]
        live = nil
        hasLiveWalk = false
        collectionsBeforeWalk = [:]
        engine = CollectionEngine(segments: [])
        loadedBox = nil
        newSegments = []
        currentArea = nil
        completions = []
        collectedOnWalk = []
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
        save()
        showAskAt()
    }

    private func record(_ walk: Walk, track: Track) {
        self.walk = walk
        self.track = track
        distanceMetres = track.distanceMetres
        var stillness = StillnessCheck(startedAt: walk.startedAt)
        track.points.forEach { stillness.add($0) }
        if let continuedAt = walk.continuedAt {
            stillness.walkContinues(at: continuedAt)
        }
        self.stillness = stillness
        showAskAt()
        let dogs = walk.dogs ?? []
        dogNames = Dictionary(dogs.map { ($0.persistentModelID, $0.name) }, uniquingKeysWith: { first, _ in first })

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
        case collections([PersistentIdentifier: DogCollection])
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
        if let last = track.points.last {
            distanceMetres += last.distance(to: point)
        }
        track.points.append(point)
        locationStatus = .recording(accuracyMetres: point.horizontalAccuracy)
        let askedAt = stillness?.askAt
        stillness?.add(point)
        if stillness?.askAt != askedAt {
            showAskAt()
        }
        if let walk, now().timeIntervalSince(lastSave) >= Self.saveInterval {
            walk.store(track, distanceMetres: distanceMetres)
            save()
            lastSave = now()
        }

        guard live != nil else { return }
        await loadSegments(around: point)
        guard !Task.isCancelled, var live else { return }
        let newlyCollected = live.add(point, using: engine)
        self.live = live
        if !newlyCollected.isEmpty {
            signals.vibrate()
            collectedOnWalk.formUnion(newlyCollected.values.joined())
        }
        showFeedback(at: point)
    }

    private func showAskAt() {
        askAt = stillness?.askAt
        if let askAt {
            signals.ask(at: askAt)
        }
    }

    /// Starts the live walk on the collections of the dogs and adds the
    /// points so far, without a vibration.
    private func startLiveWalk(on byDog: [PersistentIdentifier: DogCollection]) async {
        guard byDog.count == dogNames.count, byDog != collectionsBeforeWalk || live == nil else { return }
        collectionsBeforeWalk = byDog
        let start = CollectionEngine.LiveWalk(dogs: Set(dogNames.keys), collections: byDog)
        guard let last = track.points.last else {
            live = start
            hasLiveWalk = true
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
        showFeedback(at: last)
    }

    /// The live walk after all points of the track, with an engine for the
    /// whole track and the area around the walker. If the packages cannot
    /// be read, it uses the engine that it has, and the next point tries again.
    @concurrent nonisolated private static func replay(
        _ track: Track, on live: CollectionEngine.LiveWalk<PersistentIdentifier>, packages: MapPackages,
        engine: CollectionEngine
    ) async -> Replay {
        let last = track.points.last?.coordinate ?? CLLocationCoordinate2D()
        let loaded = try? packages.engine(around: last, withinMetres: loadRadiusMetres, covering: track)
        var live = live
        var collected: Set<Segment.ID> = []
        for point in track.points {
            collected.formUnion(live.add(point, using: loaded ?? engine).values.joined())
        }
        return Replay(loadedEngine: loaded, live: live, collected: collected)
    }

    nonisolated private struct Replay: Sendable {
        let loadedEngine: CollectionEngine?
        let live: CollectionEngine.LiveWalk<PersistentIdentifier>
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
