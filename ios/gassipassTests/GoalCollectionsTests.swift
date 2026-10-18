//
//  GoalCollectionsTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The weekly goals of `Collections` as the app uses them: the sets that a
/// phone makes, the finishes that an update stores, the swap, the status on
/// Home, and the notifications. The walks go along segments of the fixture
/// package (`FixturePackage`).
@MainActor
struct GoalCollectionsTests {
    let container: ModelContainer
    let context: ModelContext
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let segments: [Segment]
    /// Wednesday, 14 October 2026, at noon in Zurich.
    let clock = TestClock(now: try! Date("2026-10-14T12:00:00+02:00", strategy: .iso8601))
    let notifications = RecordingNotificationCenter()
    let settings = AppSettings(defaults: emptyDefaults())
    let pack: Pack
    let bello: Dog
    let luna: Dog

    init() throws {
        container = try LocalStore.inMemory()
        context = container.mainContext
        pack = Pack(name: "", createdAt: clock.now - 90 * 86_400)
        context.insert(pack)
        bello = Dog(name: "Bello", context: context)
        luna = Dog(name: "Luna", context: context)
        bello.pack = pack
        luna.pack = pack
        segments = try FixturePackage.segments()
        try context.save()
    }

    var week: DateInterval {
        WeekCalendar.week(containing: clock.now)
    }

    func collections() -> Collections {
        let clock = clock
        return Collections(
            context: context, packages: MapPackages(urls: [try! FixturePackage.url()]),
            cacheRoot: folder.appending(path: "WalkMatches", directoryHint: .isDirectory),
            reminders: GoalReminders(center: notifications, settings: settings), now: { clock.now })
    }

    /// Stores an ended walk along the segments, with a minute between them.
    @discardableResult
    func insertWalk(along segments: [Segment], dogs: [Dog], startingAt start: Date) throws -> Walk {
        var points: [TrackPoint] = []
        var time = start
        for segment in segments {
            let part = syntheticTrack(along: segment, startingAt: time)
            points += part.points
            time = part.points.last!.timestamp + 60
        }
        let walk = Walk(startedAt: start, dogs: dogs, context: context)
        walk.store(Track(points: points))
        walk.endedAt = time
        try context.save()
        return walk
    }

    @discardableResult
    func insertSet(of dog: Dog, _ goals: [WeeklyGoal], finishedAt: [Date?] = [nil, nil, nil]) throws -> StoredGoalSet {
        let set = StoredGoalSet(
            WeeklyGoalSet(
                dog: dog.id, weekStart: week.start,
                slots: zip(goals, finishedAt).map { GoalSlot(goal: $0, finishedAt: $1) }, swappedSlot: nil),
            context: context)
        try context.save()
        return set
    }

    func storedSets() throws -> [WeeklyGoalSet] {
        try container.newContext().fetchAll(StoredGoalSet.self).compactMap(\.goalSet)
    }

    @Test func thePhoneMakesASetForEachDogThatTakesPartInWalksOnce() async throws {
        luna.retire(on: clock.now - 86_400, reason: "")
        try context.save()
        let collections = collections()

        await collections.update()
        await collections.makeWeeklyGoals()
        await collections.makeWeeklyGoals()

        let sets = try storedSets()
        #expect(sets.map(\.dog) == [bello.id])
        #expect(sets.map(\.weekStart) == [week.start])
        // Bello has no walk before the week.
        #expect(sets.first?.slots.map(\.goal) == WeeklyGoals.starterGoals)
        #expect(try context.fetchAll(StoredGoalSet.self).allSatisfy(\.isWaitingToUpload))
    }

    @Test func aDogWithEarlierWalksGetsGoalsSizedFromThem() async throws {
        let segment = try #require(segments.first { $0.id == CollectionEngineTests.longSegmentID })
        for weeks in 1...4 {
            try insertWalk(along: [segment], dogs: [bello], startingAt: week.start - Double(weeks) * 7 * 86_400 + 9 * 3_600)
        }
        let collections = collections()

        await collections.update()
        await collections.makeWeeklyGoals()

        let sets = try storedSets()
        let goals = try #require(sets.first { $0.dog == bello.id }).slots.map(\.goal)
        #expect(goals != WeeklyGoals.starterGoals)
        #expect(goals.count == 3)
        // Luna has not walked yet.
        #expect(sets.first { $0.dog == luna.id }?.slots.map(\.goal) == WeeklyGoals.starterGoals)
    }

    @Test func aWalkOfTheWeekFinishesAGoalAndTheUpdateStoresTheFinish() async throws {
        let segment = try #require(segments.first { $0.id == CollectionEngineTests.longSegmentID })
        let row = try insertSet(of: bello, [.distance(metres: 10), .newLength(metres: 1), .refresh(metres: 50_000)])
        let walk = try insertWalk(along: [segment], dogs: [bello], startingAt: week.start + 86_400)
        let collections = collections()

        await collections.update()

        let set = try #require(try storedSets().first)
        #expect(set.slots[0].finishedAt == walk.endedAt)
        let collectedAt = try #require(collections.collection(of: bello.id).collected[segment.id]?.collectedAt)
        #expect(set.slots[1].finishedAt == collectedAt)
        #expect(set.slots[2].finishedAt == nil)
        #expect(row.isWaitingToUpload)
        let status = try #require(collections.goalStatus(of: bello, walks: [walk], at: clock.now))
        #expect(status.finishedCount == 2)
        #expect(status.streak == 1)
        #expect(!status.hasWeekStamp)
    }

    @Test func theWalkSummaryListsTheProgressOnEachGoal() async throws {
        let segment = try #require(segments.first { $0.id == CollectionEngineTests.longSegmentID })
        try insertSet(of: bello, [.distance(metres: 10), .newLength(metres: 50_000), .ring(5)])
        let walk = try insertWalk(along: [segment], dogs: [bello], startingAt: week.start + 86_400)
        let collections = collections()
        #expect(collections.goalProgress(of: walk, walks: [walk]) == nil)

        await collections.update()

        let lines = try #require(collections.goalProgress(of: walk, walks: [walk]))
        #expect(lines.map(\.dogName) == ["Bello", "Bello", "Bello"])
        #expect(lines.map(\.line.goal) == [.distance(metres: 10), .newLength(metres: 50_000), .ring(5)])
        #expect(lines.map(\.isFinishedOnWalk) == [true, false, false])
        #expect((lines[1].line.amountMetres ?? 0) >= segment.lengthMetres)
    }

    @Test func aFinishedGoalStaysFinishedAfterItsWalkIsDeleted() async throws {
        let segment = try #require(segments.first { $0.id == CollectionEngineTests.longSegmentID })
        try insertSet(of: bello, [.distance(metres: 10), .newLength(metres: 1), .newArea])
        let walk = try insertWalk(along: [segment], dogs: [bello], startingAt: week.start + 86_400)
        let collections = collections()
        await collections.update()
        let finished = try #require(try storedSets().first).slots.map(\.finishedAt)

        walk.markDeleted(at: clock.now)
        try context.save()
        await collections.update()

        #expect(try #require(try storedSets().first).slots.map(\.finishedAt) == finished)
        #expect(collections.goalStatus(of: bello, walks: [], at: clock.now)?.finishedCount == finished.count { $0 != nil })
    }

    @Test func aMemberSwapsOneGoalOfEachDogPerWeek() async throws {
        try insertSet(of: bello, WeeklyGoals.starterGoals)
        let collections = collections()
        await collections.update()

        #expect(collections.swapGoal(inSlot: 2, of: bello))
        #expect(!collections.swapGoal(inSlot: 1, of: bello))

        let set = try #require(try storedSets().first)
        #expect(set.slots.map(\.goal) == [.distance(metres: 1_000), .street(nil), .newArea])
        #expect(set.swappedSlot == 2)
        #expect(collections.goalStatus(of: bello, walks: [], at: clock.now)?.canSwap == false)
    }

    @Test func theSundayNotificationNamesTheGoalThatIsLeft() async throws {
        let finished = week.start + 86_400
        try insertSet(of: bello, [.distance(metres: 1_000), .street(nil), .ring(1)], finishedAt: [finished, finished, nil])
        let collections = collections()

        await collections.update()

        let sunday = try #require(notifications.planned[GoalReminders.sundayID])
        #expect(sunday.date == (try Date("2026-10-18T17:00:00+02:00", strategy: .iso8601)))
        #expect(sunday.body.contains("Bello"))
        #expect(sunday.body.contains(collections.title(of: .ring(1))))
        let monday = try #require(notifications.planned[GoalReminders.mondayID])
        #expect(monday.date == (try Date("2026-10-19T08:00:00+02:00", strategy: .iso8601)))
    }

    @Test func theSundayNotificationNamesTheGoalThatIsLeftOfEachDog() async throws {
        let finished = week.start + 86_400
        try insertSet(of: bello, [.distance(metres: 1_000), .street(nil), .ring(1)], finishedAt: [finished, finished, nil])
        try insertSet(of: luna, [.distance(metres: 1_000), .street(nil), .newArea], finishedAt: [nil, finished, finished])
        let collections = collections()

        await collections.update()

        let body = try #require(notifications.planned[GoalReminders.sundayID]?.body)
        #expect(body.contains("Bello"))
        #expect(body.contains(collections.title(of: .ring(1))))
        #expect(body.contains("Luna"))
        #expect(body.contains(collections.title(of: .distance(metres: 1_000))))
    }

    @Test func theMondayNotificationRepeatsEveryWeek() async throws {
        let collections = collections()

        await collections.update()

        #expect(notifications.planned[GoalReminders.mondayID]?.repeatsWeekly == true)
    }

    @Test func aWalkThatFinishesTheThirdGoalGivesItsSummaryTheWeekStamp() async throws {
        let segment = try #require(segments.first { $0.id == CollectionEngineTests.longSegmentID })
        let finished = week.start + 3_600
        try insertSet(of: bello, [.distance(metres: 10), .street(nil), .ring(1)], finishedAt: [nil, finished, finished])
        let walk = try insertWalk(along: [segment], dogs: [bello], startingAt: week.start + 86_400)
        let collections = collections()

        await collections.update()

        let stamps = try #require(collections.summary(of: walk)).stamps
        let stamp = try #require(stamps.first { $0.id == .weekStamp(week.start) })
        #expect(stamp.dogNames == ["Bello"])
        #expect(stamp.date == walk.endedAt)
    }

    @Test func theSundayNotificationGoesWhenTheWeekStampNeedsNoMoreGoals() async throws {
        let finished = week.start + 86_400
        let row = try insertSet(
            of: bello, [.distance(metres: 1_000), .street(nil), .ring(1)], finishedAt: [finished, finished, nil])
        let collections = collections()
        await collections.update()
        #expect(notifications.planned[GoalReminders.sundayID] != nil)

        var set = try #require(row.goalSet)
        set.slots[2].finishedAt = finished
        row.update(to: set)
        try context.save()
        await collections.update()

        #expect(notifications.planned[GoalReminders.sundayID] == nil)
        #expect(notifications.planned[GoalReminders.mondayID] != nil)
    }

    @Test func aNotificationThatIsSwitchedOffIsNotScheduled() async throws {
        let finished = week.start + 86_400
        try insertSet(of: bello, [.distance(metres: 1_000), .street(nil), .ring(1)], finishedAt: [finished, finished, nil])
        settings.notifiesAboutNewGoals = false
        settings.notifiesAboutLastGoal = false
        let collections = collections()

        await collections.update()

        #expect(notifications.planned.isEmpty)
    }

    @Test func noSundayNotificationAfterSundayEvening() async throws {
        let finished = week.start + 86_400
        try insertSet(of: bello, [.distance(metres: 1_000), .street(nil), .ring(1)], finishedAt: [finished, finished, nil])
        clock.now = try Date("2026-10-18T18:00:00+02:00", strategy: .iso8601)
        let collections = collections()

        await collections.update()

        #expect(notifications.planned[GoalReminders.sundayID] == nil)
    }
}

/// A notification center that keeps the planned notifications.
final class RecordingNotificationCenter: GoalNotificationCenter {
    private(set) var planned: [String: GoalNotification] = [:]

    func add(_ notification: GoalNotification) {
        planned[notification.id] = notification
    }

    func remove(ids: [String]) {
        for id in ids {
            planned[id] = nil
        }
    }
}
