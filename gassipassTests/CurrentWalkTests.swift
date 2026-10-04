//
//  CurrentWalkTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The tests of the current walk as the app uses it, with an in-memory
/// store, the fixture package, a location source that the test drives,
/// signals that the test records, settings in their own user defaults, and
/// a clock that the test moves.
@MainActor
struct CurrentWalkTests {
    let container: ModelContainer
    let context: ModelContext
    let packages: MapPackages
    let collections: Collections
    let segments: [Segment]
    let source = ScriptedLocationSource()
    let signals = RecordingSignals()
    let settings = AppSettings(defaults: UserDefaults(suiteName: "CurrentWalkTests-\(UUID().uuidString)")!)
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 812_000_000))
    let bello = Dog(name: "Bello")

    init() throws {
        container = try ModelContainer(
            for: Dog.self, Walk.self, CompletedArea.self, CompletedStreet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context = ModelContext(container)
        context.insert(bello)
        try context.save()
        packages = MapPackages(urls: [try FixturePackage.url()])
        collections = Collections(context: context, packages: packages, cacheRoot: nil)
        segments = try FixturePackage.segments()
    }

    func currentWalk(
        source: ScriptedLocationSource? = nil, signals: RecordingSignals? = nil, device: String = "phone"
    ) -> CurrentWalk {
        CurrentWalk(
            context: context, collections: collections, packages: packages,
            location: source ?? self.source, signals: signals ?? self.signals, settings: settings,
            deviceID: device, now: { [clock] in clock.now })
    }

    /// The straight segment in Dietikon, about 1034 m long.
    func long() throws -> Segment {
        try #require(segments.first { $0.id == CollectionEngineTests.longSegmentID })
    }

    /// A segment in Spreitenbach, 427 m long and more than 3 km from the
    /// start of the long segment.
    func spreitenbach() throws -> Segment {
        try #require(segments.first { $0.id == "{03F5E4FD-0C25-4E6D-97BE-CEA977D98AD4}" })
    }

    /// Stores a walk with the track and the dogs, ended or not.
    @discardableResult
    func insertWalk(_ track: Track, dogs: [Dog], ended: Bool) throws -> Walk {
        let walk = Walk(startedAt: try #require(track.points.first).timestamp, dogs: dogs)
        walk.store(track)
        walk.endedAt = ended ? try #require(track.points.last).timestamp : nil
        context.insert(walk)
        try context.save()
        return walk
    }

    /// Waits until the walk has handled every event so far. The walk handles
    /// one event at a time, so a status event after them shows when it is
    /// done. The status event differs from the status that the walk shows
    /// now, so that the wait never ends too early.
    func flush(_ walk: CurrentWalk) async throws {
        let (event, status): (LocationEvent, CurrentWalk.LocationStatus) =
            walk.locationStatus == .denied ? (.unavailable, .unavailable) : (.denied, .denied)
        source.send(event)
        try await eventually { walk.locationStatus == status }
    }

    // MARK: Recording

    @Test func aWalkRecordsThePointsAndStopStoresTheTrackAndTheEnd() async throws {
        let long = try long()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        let track = syntheticTrack(along: long, startingAt: clock.now)
        let recorded = try #require(walk.walk)

        source.send(track)
        try await flush(walk)
        clock.now = try #require(track.points.last).timestamp + 5
        walk.stop()

        #expect(walk.walk == nil)
        #expect(recorded.endedAt == clock.now)
        #expect(try recorded.readTrack() == track)
        try await eventually { !source.isRunning }
        await collections.update()
        #expect(collections.collection(of: bello.persistentModelID).collectedSegments.contains(long.id))
    }

    @Test func theDistanceIsTheLengthOfTheTrackSoFar() async throws {
        let walk = currentWalk()
        walk.start(dogs: [bello])
        let track = syntheticTrack(along: try long(), startingAt: clock.now)
        let recorded = try #require(walk.walk)

        source.send(Track(points: Array(track.points.prefix(50))))
        try await flush(walk)
        let halfway = walk.distanceMetres
        source.send(Track(points: Array(track.points.dropFirst(50))))
        try await flush(walk)
        walk.stop()

        #expect(halfway == Track(points: Array(track.points.prefix(50))).distanceMetres)
        #expect(recorded.distanceMetres == track.distanceMetres)
        #expect(try recorded.readTrack().distanceMetres == recorded.distanceMetres)
    }

    @Test func theTrackIsSavedThirtySecondsAfterTheLastSave() async throws {
        let walk = currentWalk()
        walk.start(dogs: [bello])
        let points = syntheticTrack(along: try long(), startingAt: clock.now).points
        func savedPointCount() throws -> Int {
            try ModelContext(container).fetch(FetchDescriptor<Walk>()).first?.readTrack().points.count ?? 0
        }

        source.send(.point(points[0]))
        try await flush(walk)
        let afterFirst = try savedPointCount()
        clock.now += 20
        source.send(.point(points[1]))
        try await flush(walk)
        let after20Seconds = try savedPointCount()
        clock.now += 10
        source.send(.point(points[2]))
        try await flush(walk)

        #expect(afterFirst == 1)
        #expect(after20Seconds == 1)
        #expect(try savedPointCount() == 3)
    }

    @Test func anUnfinishedWalkOfTheStoreContinuesWithItsPoints() async throws {
        let long = try long()
        let first = syntheticTrack(along: long, to: 0.5, startingAt: clock.now)
        let unfinished = try insertWalk(first, dogs: [bello], ended: false)

        let walk = currentWalk()
        let rest = syntheticTrack(along: long, from: 0.5, to: 1, startingAt: try #require(first.points.last).timestamp + 1)
        source.send(rest)
        try await flush(walk)
        let distance = walk.distanceMetres
        walk.stop()

        #expect(source.startCount == 1)
        #expect(try unfinished.readTrack().points == first.points + rest.points)
        #expect(distance == Track(points: first.points + rest.points).distanceMetres)
    }

    @Test func anUnfinishedWalkContinuesOnlyOnTheDeviceThatRecordsIt() throws {
        let walk = currentWalk(device: "phone")
        walk.start(dogs: [bello])
        let recorded = try #require(walk.walk)

        let ipadSource = ScriptedLocationSource()
        let onIpad = currentWalk(source: ipadSource, device: "iPad")
        let phoneSource = ScriptedLocationSource()
        let onPhoneAfterRelaunch = currentWalk(source: phoneSource, device: "phone")

        #expect(onIpad.walk == nil)
        #expect(ipadSource.startCount == 0)
        #expect(recorded.endedAt == nil)
        #expect(onPhoneAfterRelaunch.walk?.persistentModelID == recorded.persistentModelID)
        #expect(phoneSource.startCount == 1)
    }

    @Test func anUnfinishedWalkWhoseTrackCannotBeReadEndsAndKeepsItsData() throws {
        let unfinished = Walk(startedAt: clock.now - 600, dogs: [bello])
        unfinished.trackData = Data([0xFF])
        context.insert(unfinished)
        try context.save()

        let walk = currentWalk()

        #expect(walk.walk == nil)
        #expect(unfinished.endedAt == clock.now)
        #expect(unfinished.trackData == Data([0xFF]))
        #expect(source.startCount == 0)
    }

    @Test func theLocationStatusFollowsTheLocationSource() async throws {
        let walk = currentWalk()
        walk.start(dogs: [bello])
        let waiting = walk.locationStatus

        source.send(.point(TrackPoint(latitude: 47.41, longitude: 8.40, timestamp: clock.now, horizontalAccuracy: 7)))
        try await eventually { walk.locationStatus == .recording(accuracyMetres: 7) }
        source.send(.unavailable)
        try await eventually { walk.locationStatus == .unavailable }
        source.send(.denied)
        try await eventually { walk.locationStatus == .denied }

        #expect(waiting == .waiting)
    }

    // MARK: Live feedback

    @Test func aSegmentThatBecomesCollectedVibratesAndTheAreaShowsItsCompletion() async throws {
        let long = try long()
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }
        let track = syntheticTrack(along: long, startingAt: clock.now)

        source.send(track)
        try await flush(walk)

        let rebuilt = CollectionEngine(segments: segments).rebuild(dogs: ["Bello"], walks: [.init(dogs: ["Bello"], track: track)])
        #expect(walk.collectedOnWalk.contains(long.id))
        #expect(walk.collectedOnWalk == rebuilt["Bello"]?.collectedSegments)
        #expect(signals.vibrations >= 1)
        #expect(walk.currentArea?.id == 243)
        #expect(walk.completions.map(\.dogName) == ["Bello"])
        #expect((walk.completions.first?.completion.share ?? 0) > 0)
    }

    @Test func withTheVibrationSwitchedOffACollectedSegmentDoesNotVibrate() async throws {
        let long = try long()
        settings.vibratesForCollectedSegments = false
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }

        source.send(syntheticTrack(along: long, startingAt: clock.now))
        try await flush(walk)

        #expect(signals.vibrations == 0)
        #expect(walk.collectedOnWalk.contains(long.id))
    }

    @Test func switchingOnTheVibrationDuringTheWalkVibratesForTheNextCollectedSegment() async throws {
        let long = try long(), spreitenbach = try spreitenbach()
        settings.vibratesForCollectedSegments = false
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }
        let here = syntheticTrack(along: long, startingAt: clock.now)

        source.send(here)
        try await flush(walk)
        let whileOff = signals.vibrations
        settings.vibratesForCollectedSegments = true
        source.send(syntheticTrack(along: spreitenbach, startingAt: try #require(here.points.last).timestamp + 3600))
        try await flush(walk)

        #expect(whileOff == 0)
        #expect(walk.collectedOnWalk.isSuperset(of: [long.id, spreitenbach.id]))
        #expect(signals.vibrations >= 1)
    }

    @Test func switchingOffTheVibrationDuringTheWalkDoesNotVibrateForTheNextCollectedSegment() async throws {
        let long = try long(), spreitenbach = try spreitenbach()
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }
        let here = syntheticTrack(along: long, startingAt: clock.now)

        source.send(here)
        try await flush(walk)
        let whileOn = signals.vibrations
        settings.vibratesForCollectedSegments = false
        source.send(syntheticTrack(along: spreitenbach, startingAt: try #require(here.points.last).timestamp + 3600))
        try await flush(walk)

        #expect(whileOn >= 1)
        #expect(walk.collectedOnWalk.contains(spreitenbach.id))
        #expect(signals.vibrations == whileOn)
    }

    @Test func aSegmentThatTheDogCollectedBeforeTheWalkDoesNotVibrate() async throws {
        let long = try long()
        try insertWalk(syntheticTrack(along: long, startingAt: clock.now - 86_400), dogs: [bello], ended: true)
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }

        source.send(syntheticTrack(along: long, startingAt: clock.now))
        try await flush(walk)

        #expect(signals.vibrations == 0)
        #expect(walk.collectedOnWalk.isEmpty)
    }

    @Test func afterAResumeTheReplayDoesNotVibrateButTheNextPointsDo() async throws {
        let long = try long(), spreitenbach = try spreitenbach()
        let first = syntheticTrack(along: long, startingAt: clock.now)
        try insertWalk(first, dogs: [bello], ended: false)
        await collections.update()

        let walk = currentWalk()
        try await eventually { walk.isReady }
        let afterReplay = signals.vibrations
        let replayed = walk.collectedOnWalk
        source.send(syntheticTrack(along: spreitenbach, startingAt: try #require(first.points.last).timestamp + 3600))
        try await flush(walk)

        #expect(afterReplay == 0)
        #expect(replayed.contains(long.id))
        #expect(signals.vibrations >= 1)
        #expect(walk.collectedOnWalk.contains(spreitenbach.id))
    }

    @Test func theFeedbackWaitsForTheCollections() async throws {
        let long = try long()
        let walk = currentWalk()
        walk.start(dogs: [bello])

        source.send(syntheticTrack(along: long, startingAt: clock.now))
        try await flush(walk)
        let readyBefore = walk.isReady
        let areaBefore = walk.currentArea
        let collectedBefore = walk.collectedOnWalk
        await collections.update()
        try await eventually { walk.isReady }

        #expect(!readyBefore)
        #expect(areaBefore == nil)
        #expect(collectedBefore.isEmpty)
        #expect(walk.collectedOnWalk.contains(long.id))
        #expect(walk.currentArea?.id == 243)
        #expect(signals.vibrations == 0)
    }

    @Test func aWalkCollectsSegmentsFarFromWhereItStarted() async throws {
        let long = try long(), spreitenbach = try spreitenbach()
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }
        let here = syntheticTrack(along: long, startingAt: clock.now)
        let there = syntheticTrack(along: spreitenbach, startingAt: try #require(here.points.last).timestamp + 3600)

        source.send(Track(points: here.points + there.points))
        try await flush(walk)

        #expect(walk.collectedOnWalk.isSuperset(of: [long.id, spreitenbach.id]))
    }

    // MARK: Asking whether the walk has ended

    /// A point near Dietikon station, the given metres north of it.
    func point(north metres: Double, at date: Date) -> TrackPoint {
        TrackPoint(latitude: 47.4045 + metres / LineInMetres.metresPerDegreeLatitude, longitude: 8.4003,
                   timestamp: date, horizontalAccuracy: 5)
    }

    @Test func theWalkAsksAnHourAfterTheLastMovementOrAnswerAlsoAfterAResume() async throws {
        let start = clock.now
        let walk = currentWalk()
        walk.start(dogs: [bello])
        let atStart = walk.askAt

        source.send(.point(point(north: 0, at: start + 60)))
        source.send(.point(point(north: 100, at: start + 120)))
        try await flush(walk)
        let afterMovement = walk.askAt
        clock.now = start + 4000
        walk.continueWalk()
        let afterAnswer = walk.askAt
        let resumed = currentWalk(source: ScriptedLocationSource(), signals: RecordingSignals())

        #expect(atStart == start + 3600)
        #expect(afterMovement == start + 120 + 3600)
        #expect(afterAnswer == start + 4000 + 3600)
        #expect(resumed.askAt == start + 4000 + 3600)
    }

    @Test func theNotificationFollowsTheTimeToAskAndEndsWithTheWalk() async throws {
        let start = clock.now
        let walk = currentWalk()
        walk.start(dogs: [bello])

        source.send(.point(point(north: 0, at: start + 60)))
        source.send(.point(point(north: 100, at: start + 120)))
        try await flush(walk)
        clock.now = start + 4000
        walk.continueWalk()
        walk.stop()

        #expect(signals.asks == [start + 3600, start + 120 + 3600, start + 4000 + 3600])
        #expect(signals.stoppedAsking == 1)
    }
}

// MARK: Test adapters

/// A location source that delivers the events that the test sends.
@MainActor
final class ScriptedLocationSource: LocationSource {
    private var continuation: AsyncStream<LocationEvent>.Continuation?
    private(set) var startCount = 0
    private(set) var isRunning = false

    func start() -> AsyncStream<LocationEvent> {
        let (events, continuation) = AsyncStream<LocationEvent>.makeStream()
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.isRunning = false }
        }
        self.continuation = continuation
        startCount += 1
        isRunning = true
        return events
    }

    func send(_ event: LocationEvent) {
        continuation?.yield(event)
    }

    func send(_ track: Track) {
        track.points.forEach { send(.point($0)) }
    }
}

/// Signals that only count what the walk asks for.
@MainActor
final class RecordingSignals: WalkSignals {
    private(set) var vibrations = 0
    private(set) var asks: [Date] = []
    private(set) var stoppedAsking = 0

    func prepare() {}

    func vibrate() {
        vibrations += 1
    }

    func ask(at date: Date) {
        asks.append(date)
    }

    func stopAsking() {
        stoppedAsking += 1
    }
}

/// A clock that the test moves.
@MainActor
final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

/// Waits until the condition is true, for the work that the current walk
/// does in its own tasks.
@MainActor
func eventually(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("The condition did not become true in time.", sourceLocation: sourceLocation)
            throw CancellationError()
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}
