//
//  CurrentWalkTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import CoreLocation
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
    let settings = AppSettings(defaults: emptyDefaults())
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 812_000_000))
    let bello: Dog

    init() throws {
        container = try LocalStore.inMemory()
        context = container.mainContext
        bello = Dog(name: "Bello", context: context)
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
        let walk = Walk(startedAt: try #require(track.points.first).timestamp, dogs: dogs, context: context)
        walk.store(track)
        walk.endedAt = ended ? try #require(track.points.last).timestamp : nil
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
        #expect(collections.collection(of: bello.id).collectedSegments.contains(long.id))
    }

    /// Without an account, the person on the phone is the pack owner, and an
    /// empty name means the pack owner.
    @Test func aWalkOfThePackOwnerStoresAnEmptyNameAndCountsForTheDog() async throws {
        let luna = try Packs(context: context).addDog(named: "Luna")
        let long = try long()
        let walk = currentWalk()

        walk.start(dogs: [luna])
        source.send(syntheticTrack(along: long, startingAt: clock.now))
        try await flush(walk)
        walk.stop()

        let walks = try container.newContext().fetchAll(Walk.self)
        #expect(walks.map(\.memberName) == [""])
        await collections.update()
        #expect(collections.collection(of: luna.id).collectedSegments.contains(long.id))
    }

    @Test func aWalkKeepsTheNameOfTheMemberWhoRecordsIt() throws {
        let walk = CurrentWalk(
            context: context, collections: collections, packages: packages, location: source, signals: signals,
            settings: settings, deviceID: "phone", memberName: { "Anna" }, now: { [clock] in clock.now })
        walk.start(dogs: [bello])
        walk.stop()

        #expect(try container.newContext().fetchAll(Walk.self).map(\.memberName) == ["Anna"])
    }

    @Test func aStoppedWalkAndItsDogsWaitToUpload() throws {
        let walk = currentWalk()
        walk.start(dogs: [bello])
        clock.now += 600
        walk.stop()

        let other = container.newContext()
        let walks = try other.fetchAll(Walk.self)
        #expect(walks.map(\.isWaitingToUpload) == [true])
        #expect(walks.map(\.changedAt) == [clock.now])
        #expect(try other.fetchAll(WalkDog.self).map { $0.dog?.name } == ["Bello"])
        #expect(try other.fetchAll(WalkDog.self).allSatisfy { $0.isWaitingToUpload })
    }

    @Test func theDistanceIsTheLengthOfTheTrackSoFar() async throws {
        let walk = currentWalk()
        walk.start(dogs: [bello])
        // The shortest step that counts is the accuracy, 12 m. The points
        // are 5 m apart, so each step is about 10 m or 15 m.
        let track = syntheticTrack(along: try long(), accuracy: 12, startingAt: clock.now)
        let recorded = try #require(walk.walk)

        source.send(Track(points: Array(track.points.prefix(50))))
        try await flush(walk)
        let halfway = walk.distanceMetres
        source.send(Track(points: Array(track.points.dropFirst(50))))
        try await flush(walk)
        walk.stop()

        // Core Location on the iOS 27 simulator gives a slightly different
        // distance for the same two points from one call to the next. With
        // steps near the shortest step, a step could count in one sum and
        // not in the other.
        #expect(abs(halfway - Track(points: Array(track.points.prefix(50))).distanceMetres) < 0.5)
        #expect(abs(recorded.distanceMetres - track.distanceMetres) < 0.5)
        #expect(abs(try recorded.readTrack().distanceMetres - recorded.distanceMetres) < 0.5)
    }

    @Test func theTrackIsSavedThirtySecondsAfterTheLastSave() async throws {
        let walk = currentWalk()
        walk.start(dogs: [bello])
        let points = syntheticTrack(along: try long(), startingAt: clock.now).points
        let other = container.newContext()
        func savedPointCount() throws -> Int {
            try other.fetchAll(Walk.self).first?.readTrack().points.count ?? 0
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
        // Accuracy 12 m, for the same reason as in theDistanceIsTheLengthOfTheTrackSoFar().
        let first = syntheticTrack(along: long, to: 0.5, accuracy: 12, startingAt: clock.now)
        let unfinished = try insertWalk(first, dogs: [bello], ended: false)

        let walk = currentWalk()
        let rest = syntheticTrack(
            along: long, from: 0.5, to: 1, accuracy: 12, startingAt: try #require(first.points.last).timestamp + 1)
        source.send(rest)
        try await flush(walk)
        let distance = walk.distanceMetres
        walk.stop()

        #expect(source.startCount == 1)
        #expect(try unfinished.readTrack().points == first.points + rest.points)
        #expect(abs(distance - Track(points: first.points + rest.points).distanceMetres) < 0.5)
    }

    /// A backup that the user restores to a new phone brings the unfinished
    /// walk, but the new phone has another device ID. An unfinished walk
    /// never leaves its phone, so the new phone continues it (#131).
    @Test func anUnfinishedWalkWithAnotherDeviceIDContinuesAfterARestore() throws {
        let walk = currentWalk(device: "old phone")
        walk.start(dogs: [bello])
        let recorded = try #require(walk.walk)
        let newSource = ScriptedLocationSource()

        let onNewPhone = currentWalk(source: newSource, device: "new phone")

        #expect(onNewPhone.walk?.id == recorded.id)
        #expect(newSource.startCount == 1)
        #expect(recorded.endedAt == nil)
    }

    @Test func anUnfinishedWalkWhoseTrackCannotBeReadEndsAndKeepsItsData() throws {
        let unfinished = Walk(startedAt: clock.now - 600, dogs: [bello], context: context)
        unfinished.trackData = Data([0xFF])
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

    // MARK: Stamps

    /// The segments of Oetwil an der Limmat, the longest last.
    func oetwil() -> [Segment] {
        segments.filter { $0.area == 246 }.sorted { $0.lengthMetres < $1.lengthMetres }
    }

    /// A walk along each of the segments, one after the other, with a minute
    /// between them.
    func track(along segments: [Segment], startingAt start: Date) -> Track {
        var points: [TrackPoint] = []
        var time = start
        for segment in segments {
            let part = syntheticTrack(along: segment, startingAt: time)
            points += part.points
            time = part.points.last!.timestamp + 60
        }
        return Track(points: points)
    }

    /// Stores an ended walk of Bello a day ago along the segments of Oetwil
    /// an der Limmat but the longest ones, and returns the longest ones. They
    /// are the fewest of the longest segments that make more than 5% of the
    /// area, so that a walk along them completes it. The test checks that the
    /// earlier walk leaves the area at 75% or more.
    func walkOetwilButTheLongestSegments() async throws -> [Segment] {
        var oetwil = oetwil()
        await collections.update()
        let area = try #require(collections.areas[246])
        var longest: [Segment] = []
        while longest.reduce(0, { $0 + $1.lengthMetres }) <= 0.05 * area.lengthMetres {
            longest.insert(try #require(oetwil.last), at: 0)
            oetwil.removeLast()
        }
        try insertWalk(track(along: oetwil, startingAt: clock.now - 86_400), dogs: [bello], ended: true)
        await collections.update()
        try #require(collections.collection(of: bello.id).completion(of: area).share >= 0.75)
        return longest
    }

    /// The steps of the area stamp that the walk reported for the area, in order.
    func reportedSteps(of area: Area.ID, in walk: CurrentWalk) -> [StampStep] {
        walk.completedOnWalk.compactMap {
            guard case let .area(id, step) = $0.id, id == area else { return nil }
            return step
        }
    }

    @Test func aWalkReportsTheEntryStampOfAnArea() async throws {
        let segment = try #require(oetwil().dropLast().last)
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }

        source.send(syntheticTrack(along: segment, startingAt: clock.now))
        try await flush(walk)

        #expect(reportedSteps(of: 246, in: walk) == [.entry])
        let stamp = try #require(walk.completedOnWalk.first { $0.id == .area(246, .entry) })
        #expect(stamp.name == "Oetwil an der Limmat")
        #expect(stamp.dogNames == ["Bello"])
    }

    @Test func aWalkThatCompletesAnAreaReportsItsFullStamp() async throws {
        let longest = try await walkOetwilButTheLongestSegments()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }

        source.send(track(along: longest, startingAt: clock.now))
        try await flush(walk)

        #expect(reportedSteps(of: 246, in: walk) == [.completed])
    }

    @Test func aDogWithTheFullStampOfAnAreaGetsNoStampOfTheAreaAgain() async throws {
        let longest = try await walkOetwilButTheLongestSegments()
        try insertWalk(track(along: longest, startingAt: clock.now - 3_600), dogs: [bello], ended: true)
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }

        source.send(track(along: longest, startingAt: clock.now))
        try await flush(walk)

        #expect(walk.completedOnWalk.isEmpty)
    }

    // MARK: Weekly goals

    /// Stores a set of weekly goals of Bello for the week of the clock.
    func insertGoals(_ goals: [WeeklyGoal], finishedAt: [Date?] = [nil, nil, nil]) async throws {
        _ = StoredGoalSet(
            WeeklyGoalSet(
                dog: bello.id, weekStart: WeekCalendar.week(containing: clock.now).start,
                slots: zip(goals, finishedAt).map { GoalSlot(goal: $0, finishedAt: $1) }, swappedSlot: nil),
            context: context)
        try context.save()
        await collections.update()
    }

    func reportedGoals(in walk: CurrentWalk) -> [WeeklyGoal] {
        walk.completedOnWalk.compactMap {
            guard case let .weeklyGoal(goal) = $0.id else { return nil }
            return goal
        }
    }

    @Test func aWalkThatFinishesAWeeklyGoalShowsItOnTheMap() async throws {
        try await insertGoals([.distance(metres: 500), .newLength(metres: 50_000), .refresh(metres: 50_000)])
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }

        source.send(syntheticTrack(along: try long(), startingAt: clock.now))
        try await flush(walk)

        #expect(reportedGoals(in: walk) == [.distance(metres: 500)])
        let stamp = try #require(walk.completedOnWalk.first { $0.id == .weeklyGoal(.distance(metres: 500)) })
        #expect(stamp.name == collections.title(of: .distance(metres: 500)))
        #expect(stamp.dogNames == ["Bello"])
    }

    @Test func aWalkThatEntersAnAreaFinishesTheGoalOfANewArea() async throws {
        try await insertGoals([.distance(metres: 50_000), .newLength(metres: 50_000), .newArea])
        let segment = try #require(oetwil().dropLast().last)
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }

        source.send(syntheticTrack(along: segment, startingAt: clock.now))
        try await flush(walk)

        #expect(reportedGoals(in: walk).contains(.newArea))
    }

    @Test func aGoalThatWasFinishedBeforeTheWalkDoesNotShowAgain() async throws {
        try await insertGoals(
            [.distance(metres: 500), .newLength(metres: 50_000), .refresh(metres: 50_000)],
            finishedAt: [clock.now - 3_600, nil, nil])
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }

        source.send(syntheticTrack(along: try long(), startingAt: clock.now))
        try await flush(walk)

        #expect(reportedGoals(in: walk).isEmpty)
    }

    // MARK: Rings

    /// Gives Bello a pack whose home base lies at the middle of the long
    /// segment, and returns the segments of ring 1 around it.
    func homeBaseAtTheLongSegment() throws -> (home: HomeBase, ring1: [Segment]) {
        let long = try long()
        let first = try #require(long.coordinates.first), last = try #require(long.coordinates.last)
        let home = HomeBase(latitude: (first.latitude + last.latitude) / 2, longitude: (first.longitude + last.longitude) / 2)
        let pack = Pack(name: "", createdAt: clock.now)
        context.insert(pack)
        bello.pack = pack
        pack.setHomeBase(home, at: clock.now)
        try context.save()
        let ids = Set(RingSegments(centre: home, segments: segments, radiusMetres: 250).segments.map(\.id))
        return (home, segments.filter { ids.contains($0.id) }.sorted { $0.id < $1.id })
    }

    @Test func aWalkThatCompletesTheRingReportsTheRingStampAndTheMapShowsTheRingAndTheCollectedSegments() async throws {
        let (home, ring1) = try homeBaseAtTheLongSegment()
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }
        #expect(walk.currentRing == Ring(number: 1, centre: home))
        #expect(walk.markedFeatures.all.isEmpty)
        let recorded = track(along: ring1, startingAt: clock.now)

        source.send(recorded)
        try await flush(walk)

        let stamps = walk.completedOnWalk.filter { if case .ring = $0.id { true } else { false } }
        #expect(stamps.map(\.id) == [.ring(Ring(number: 1, centre: home))])
        #expect(stamps.first?.dogNames == ["Bello"])
        #expect(walk.currentRing == Ring(number: 2, centre: home))
        #expect(walk.markedFeatures.all.isSuperset(of: ring1.map(\.fid)))

        clock.now = try #require(recorded.points.last).timestamp + 5
        walk.stop()
        await collections.update()
        let ended = try #require(walk.endedWalk)
        let summary = try #require(collections.summary(of: ended))
        let inSummary = summary.stamps.filter { if case .ring = $0.id { true } else { false } }
        #expect(inSummary.map(\.id) == [.ring(Ring(number: 1, centre: home))])
        #expect(inSummary.first?.date == collections.ringRecords(of: bello.id).first?.date)
    }

    @Test func aDogWithTheRingStampGetsNoRingStampAgainWhenAMapReleaseReopensTheRing() async throws {
        let (home, ring1) = try homeBaseAtTheLongSegment()
        _ = CompletedRing(dogID: bello.id, ring: Ring(number: 1, centre: home), completedAt: clock.now - 86_400, context: context)
        try context.save()
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }

        source.send(track(along: ring1, startingAt: clock.now))
        try await flush(walk)

        #expect(!walk.completedOnWalk.contains { $0.id == .ring(Ring(number: 1, centre: home)) })
        #expect(walk.currentRing?.number == 2)
    }

    // MARK: Marks

    /// Bello walked the long segment 22 days ago. This walk covers it
    /// again, so the map shows its mark fresh again, without a vibration,
    /// and the summary lists the refreshed length.
    @Test func aWalkRefreshesTheMarksOnTheMapWithoutAVibrationAndTheSummaryListsTheirLength() async throws {
        let long = try long()
        let earlier = syntheticTrack(along: long, startingAt: clock.now - 22 * 86_400)
        try insertWalk(earlier, dogs: [bello], ended: true)
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }
        let collectedBefore = collections.collection(of: bello.id).collected
        #expect(walk.markedFeatures.bands[3].contains(long.fid))
        let recorded = syntheticTrack(along: long, from: 1, to: 0, startingAt: clock.now)

        source.send(recorded)
        try await flush(walk)

        #expect(walk.markedFeatures.bands[0].contains(long.fid))
        #expect(walk.markedFeatures.all == Set(collectedBefore.values.map(\.fid)))
        #expect(walk.collectedOnWalk.isEmpty)
        #expect(signals.vibrations == 0)

        clock.now = try #require(recorded.points.last).timestamp + 5
        walk.stop()
        await collections.update()
        let ended = try #require(walk.endedWalk)
        let summary = try #require(collections.summary(of: ended))
        #expect(summary.newSegmentCount == 0)
        // The walk covers again everything that the earlier walk collected.
        let length = collectedBefore.values.reduce(0) { $0 + $1.lengthMetres }
        #expect(abs(summary.refreshedLengthMetres - length) < 1e-6)
        #expect(summary.refreshedLengthMetres >= long.lengthMetres)
    }

    @Test func theSummaryCountsASegmentThatIsNewForOneDogAsNewAndNotAsRefreshed() async throws {
        let luna = Dog(name: "Luna", context: context)
        let long = try long()
        try insertWalk(syntheticTrack(along: long, startingAt: clock.now - 2 * 86_400), dogs: [bello], ended: true)
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello, luna])
        try await eventually { walk.isReady }
        let recorded = syntheticTrack(along: long, from: 1, to: 0, startingAt: clock.now)
        source.send(recorded)
        try await flush(walk)
        clock.now = try #require(recorded.points.last).timestamp + 5

        walk.stop()
        await collections.update()

        let ended = try #require(walk.endedWalk)
        let summary = try #require(collections.summary(of: ended))
        #expect(summary.newSegmentCount > 0)
        #expect(summary.refreshedLengthMetres == 0)
    }

    // MARK: Summary

    @Test func theWalkEndsOnASummaryOfWhatItEarnedAfterTheCollectionUpdate() async throws {
        let longest = try await walkOetwilButTheLongestSegments()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }
        let recorded = track(along: longest, startingAt: clock.now)
        source.send(recorded)
        try await flush(walk)
        clock.now = try #require(recorded.points.last).timestamp + 5
        let collectedOnWalk = walk.collectedOnWalk

        walk.stop()

        let ended = try #require(walk.endedWalk)
        #expect(walk.walk == nil)
        #expect(collections.summary(of: ended) == nil)
        await collections.update()
        let summary = try #require(collections.summary(of: ended))
        #expect(summary.distanceMetres == ended.distanceMetres)
        #expect(summary.distanceMetres > 0)
        #expect(summary.newSegmentCount == collectedOnWalk.count)
        #expect(summary.newSegmentCount > 0)
        // The area stamp shows once, with the step that the walk reached.
        let areaStamps = summary.stamps.filter { if case .area = $0.id { true } else { false } }
        #expect(areaStamps.map(\.id) == [.area(246, .completed)])
        #expect(areaStamps.first?.dogNames == ["Bello"])
        #expect(areaStamps.first?.date == bello.completedAreas?.first?.completedAt)
        #expect(summary.stamps.map(\.date) == summary.stamps.map(\.date).sorted())

        walk.closeSummary()
        #expect(walk.endedWalk == nil)
    }

    /// Bello completes Oetwil an der Limmat, and Luna gets only its entry
    /// stamp. The map shows each stamp when the dog earns it. The stamp of an
    /// area grows in one place, so the area shows once in the summary.
    @Test func anAreaShowsOnceWithTheHighestStepAndTheDogsThatReachedIt() async throws {
        let luna = Dog(name: "Luna", context: context)
        try context.save()
        let longest = try await walkOetwilButTheLongestSegments()
        let walk = currentWalk()
        walk.start(dogs: [bello, luna])
        try await eventually { walk.isReady }
        let recorded = track(along: longest, startingAt: clock.now)
        source.send(recorded)
        try await flush(walk)
        clock.now = try #require(recorded.points.last).timestamp + 5
        let onMap = walk.completedOnWalk.filter { if case .area = $0.id { true } else { false } }

        walk.stop()
        await collections.update()

        #expect(Set(onMap.map(\.id)) == [.area(246, .completed), .area(246, .entry)])
        #expect(onMap.first { $0.id == .area(246, .completed) }?.dogNames == ["Bello"])
        #expect(onMap.first { $0.id == .area(246, .entry) }?.dogNames == ["Luna"])
        let ended = try #require(walk.endedWalk)
        let summary = try #require(collections.summary(of: ended))
        let inSummary = summary.stamps.filter { if case .area = $0.id { true } else { false } }
        #expect(inSummary.map(\.id) == [.area(246, .completed)])
        #expect(inSummary.map(\.dogNames) == [["Bello"]])
    }

    @Test func theSummaryDoesNotWaitForADogThatWasDeletedDuringTheWalk() async throws {
        let luna = Dog(name: "Luna", context: context)
        try context.save()
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello, luna])
        try await eventually { walk.isReady }
        let recorded = syntheticTrack(along: try long(), startingAt: clock.now)
        source.send(recorded)
        try await flush(walk)
        clock.now = try #require(recorded.points.last).timestamp + 5

        luna.markDeleted()
        try context.save()
        walk.stop()
        await collections.update()

        let ended = try #require(walk.endedWalk)
        let summary = try #require(collections.summary(of: ended))
        #expect(summary.newSegmentCount > 0)
    }

    /// Another member removes this person from the pack during the walk, and
    /// the next download removes the pack from this phone after the stop.
    @Test func theSummaryClosesWhenItsWalkLeavesThePhone() async throws {
        let walk = currentWalk()
        walk.start(dogs: [bello])
        walk.stop()
        #expect(walk.endedWalk != nil)

        try LocalStore.removePack(from: context)

        #expect(walk.endedWalk == nil)
    }

    @Test func theSummaryOfAWalkListsOnlyTheStampsOfThatWalk() async throws {
        let longest = try await walkOetwilButTheLongestSegments()
        try insertWalk(track(along: longest, startingAt: clock.now - 3_600), dogs: [bello], ended: true)
        await collections.update()
        let walk = currentWalk()
        walk.start(dogs: [bello])
        try await eventually { walk.isReady }
        source.send(track(along: longest, startingAt: clock.now))
        try await flush(walk)

        walk.stop()
        await collections.update()

        let ended = try #require(walk.endedWalk)
        let summary = try #require(collections.summary(of: ended))
        #expect(summary.newSegmentCount == 0)
        #expect(summary.stamps.isEmpty)
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
