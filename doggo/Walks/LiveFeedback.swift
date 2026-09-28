//
//  LiveFeedback.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import AudioToolbox
import CoreLocation
import Observation
import SwiftData

/// The feedback during a walk: the segments near the walker that are new for
/// at least one dog on the walk, a short vibration when a segment becomes
/// collected for any dog on the walk, the live completion of the current
/// area for each dog, and the segments collected on the walk. The walk
/// recorder gives it the points of the walk, and the live mode of the
/// collection engine applies the rules.
///
/// It needs no network, because the map packages are bundled. It also runs
/// while the phone is locked, so that the phone vibrates in the pocket.
@Observable
final class LiveFeedback {
    /// The live completion of one dog on the walk.
    struct DogCompletion: Identifiable {
        let id: PersistentIdentifier
        let dogName: String
        let completion: Completion
    }

    /// The map shows the new segments within this distance of the walker.
    static let nearRadiusMetres = 500.0
    /// The engine holds the segments within this distance of the point where
    /// they were loaded. When the walker comes near the edge of that box, it
    /// loads the segments around the walker again.
    private static let loadRadiusMetres = 1500.0

    /// The segments near the walker that are new for at least one dog on the walk.
    private(set) var newSegments: [Segment] = []
    /// The area that the walker is in, or nil before it is known.
    private(set) var currentArea: Area?
    /// The live completion of the current area for each dog on the walk, sorted by name.
    private(set) var completions: [DogCompletion] = []
    /// The segments that became collected on this walk for at least one dog on the walk.
    private(set) var collectedOnWalk: Set<Segment.ID> = []

    private let collections: Collections
    private var packages: [MapPackage]?
    private var dogNames: [PersistentIdentifier: String] = [:]
    private var track = Track()
    /// The live walk, or nil until the collections of all dogs on the walk
    /// are known. Until then the feedback shows nothing, so that it does not
    /// report segments that the dogs have already collected.
    private var live: CollectionEngine.LiveWalk<PersistentIdentifier>?
    /// The collections of the dogs from their ended walks, that the live walk started on.
    private var collectionsBeforeWalk: [PersistentIdentifier: DogCollection] = [:]
    private var engine = CollectionEngine(segments: [])
    private var loadedBox: CoordinateBox?
    private var collectionUpdates: Task<Void, Never>?

    init(collections: Collections) {
        self.collections = collections
    }

    /// Starts the feedback for a walk, also for a walk that continues with
    /// the points that it has already recorded.
    func start(dogs: [Dog], track: Track) {
        stop()
        dogNames = Dictionary(dogs.map { ($0.persistentModelID, $0.name) }, uniquingKeysWith: { first, _ in first })
        self.track = track
        let dogIDs = Set(dogNames.keys)
        // The collections change when the first rebuild after the start of
        // the app ends. The live walk then starts again on the new collections.
        collectionUpdates = Task { [weak self, collections] in
            for await byDog in Observations({ collections.byDog }) {
                guard let self, !Task.isCancelled else { return }
                self.startLiveWalk(on: byDog.filter { dogIDs.contains($0.key) })
            }
        }
    }

    /// Adds the next point of the walk. The phone vibrates when a segment
    /// becomes collected for any dog on the walk.
    func add(_ point: TrackPoint) {
        track.points.append(point)
        guard live != nil else { return }
        loadSegments(around: point)
        let newlyCollected = live?.add(point, using: engine) ?? [:]
        if !newlyCollected.isEmpty {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            newlyCollected.values.forEach { collectedOnWalk.formUnion($0) }
        }
        showFeedback(at: point)
    }

    /// Ends the feedback when the walk ends.
    func stop() {
        collectionUpdates?.cancel()
        collectionUpdates = nil
        dogNames = [:]
        track = Track()
        live = nil
        collectionsBeforeWalk = [:]
        engine = CollectionEngine(segments: [])
        loadedBox = nil
        newSegments = []
        currentArea = nil
        completions = []
        collectedOnWalk = []
    }

    /// Starts the live walk on the collections of the dogs and adds the
    /// points so far, without a vibration.
    private func startLiveWalk(on byDog: [PersistentIdentifier: DogCollection]) {
        guard byDog.count == dogNames.count, byDog != collectionsBeforeWalk || live == nil else { return }
        collectionsBeforeWalk = byDog
        var live = CollectionEngine.LiveWalk(dogs: Set(dogNames.keys), collections: byDog)
        guard let last = track.points.last else {
            self.live = live
            return
        }
        // An engine with the segments that the whole track can cover and
        // the segments around the walker.
        let box = CollectionEngine.box(around: last.coordinate, withinMetres: Self.loadRadiusMetres)
        engine = CollectionEngine(segments: segments(in: CollectionEngine.coverableBoxes(of: track) + [box]))
        loadedBox = box
        var collectedOnWalk: Set<Segment.ID> = []
        for point in track.points {
            live.add(point, using: engine).values.forEach { collectedOnWalk.formUnion($0) }
        }
        self.live = live
        self.collectedOnWalk = collectedOnWalk
        showFeedback(at: last)
    }

    /// Makes sure that the engine holds every segment near the point.
    private func loadSegments(around point: TrackPoint) {
        let needed = CollectionEngine.box(around: point.coordinate, withinMetres: Self.nearRadiusMetres)
        if let loadedBox, loadedBox.contains(needed) { return }
        let box = CollectionEngine.box(around: point.coordinate, withinMetres: Self.loadRadiusMetres)
        engine = CollectionEngine(segments: segments(in: [box]))
        loadedBox = box
    }

    /// The segments of the bundled packages in the boxes. The packages open
    /// when they are first needed.
    private func segments(in boxes: [CoordinateBox]) -> [Segment] {
        if packages == nil {
            packages = (try? MapPackage.bundled()) ?? []
        }
        return MapPackage.segments(in: boxes, of: packages ?? [])
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
