//
//  WeeklyGoalsTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import Testing
@testable import gassipass

/// The rules of the weekly goals, with synthetic walks and collections.
struct WeeklyGoalsTests {
    let dog = UUID()
    /// Monday, 12 October 2026, at midnight in Zurich.
    let week = WeekCalendar.week(containing: try! Date("2026-10-14T12:00:00+02:00", strategy: .iso8601))

    /// A time in the week of the test: the day from Monday (0) and the hour.
    private func time(day: Int, hour: Double = 9, week offset: Int = 0) -> Date {
        WeekCalendar.weekStart(week.start, movedBy: offset) + Double(day) * 86_400 + hour * 3_600
    }

    private func walk(
        day: Int, hour: Double = 9, week offset: Int = 0, metres: Double = 1_000, marks: [Segment.ID: Double] = [:]
    ) -> GoalWalk {
        let start = time(day: day, hour: hour, week: offset)
        return GoalWalk(
            id: UUID(), startedAt: start, endedAt: start + 3_600, distanceMetres: metres,
            marks: marks.mapValues { start + $0 * 60 })
    }

    private func collected(_ id: Segment.ID, metres: Double = 100, at date: Date) -> (Segment.ID, CollectedSegment) {
        (id, CollectedSegment(fid: 0, area: 1, street: nil, lengthMetres: metres, collectedAt: date, markedAt: date))
    }

    private func collection(_ segments: [(Segment.ID, CollectedSegment)]) -> DogCollection {
        DogCollection(coveredParts: [:], collected: Dictionary(uniqueKeysWithValues: segments))
    }

    private func events(
        walks: [GoalWalk] = [], collection: DogCollection = DogCollection(), records: GoalRecords = GoalRecords()
    ) -> GoalEvents {
        GoalEvents(week: week, collection: collection, walks: walks, records: records)
    }

    // MARK: Progress

    @Test func aDistanceGoalFinishesAtTheEndOfTheWalkThatReachesIt() {
        let walks = [walk(day: 0, metres: 2_000), walk(day: 2, metres: 2_500), walk(day: 4, metres: 1_000)]
        let progress = WeeklyGoals.progress(of: .distance(metres: 4_000), in: events(walks: walks))

        #expect(progress.amountMetres == 5_500)
        #expect(progress.finishedAt == walks[1].endedAt)
    }

    @Test func onlyTheWalksThatStartInTheWeekCount() {
        let walks = [walk(day: 6, hour: 23.5, week: -1, metres: 3_000), walk(day: 0, metres: 500)]
        let progress = WeeklyGoals.progress(of: .distance(metres: 1_000), in: events(walks: walks))

        #expect(progress.amountMetres == 500)
        #expect(progress.finishedAt == nil)
    }

    @Test func aNewLengthGoalCountsTheSegmentsCollectedInTheWeek() {
        let collection = collection([
            collected("old", metres: 400, at: time(day: 3, week: -1)),
            collected("a", metres: 300, at: time(day: 1)),
            collected("b", metres: 300, at: time(day: 2)),
        ])
        let progress = WeeklyGoals.progress(of: .newLength(metres: 500), in: events(collection: collection))

        #expect(progress.amountMetres == 600)
        #expect(progress.finishedAt == time(day: 2))
    }

    /// A segment last marked three weeks ago counts. A segment that a walk
    /// of last week marked does not, and neither does a segment that the
    /// walk collects.
    @Test func aRefreshGoalCountsOnlyMarksOlderThanTwoWeeks() {
        let collection = collection([
            collected("old", metres: 200, at: time(day: 0, week: -3)),
            collected("recent", metres: 300, at: time(day: 0, week: -3)),
            collected("new", metres: 400, at: time(day: 1, hour: 9.5)),
        ])
        let walks = [
            walk(day: 3, week: -1, marks: ["recent": 10]),
            walk(day: 1, marks: ["old": 10, "recent": 20, "new": 40]),
        ]
        let progress = WeeklyGoals.progress(of: .refresh(metres: 200), in: events(walks: walks, collection: collection))

        #expect(progress.amountMetres == 200)
        #expect(progress.finishedAt == walks[1].marks["old"])
    }

    @Test func aSegmentRefreshedTwiceInTheWeekCountsOnce() {
        let collection = collection([collected("old", metres: 200, at: time(day: 0, week: -3))])
        let walks = [walk(day: 1, marks: ["old": 10]), walk(day: 4, marks: ["old": 10])]
        let progress = WeeklyGoals.progress(of: .refresh(metres: 300), in: events(walks: walks, collection: collection))

        #expect(progress.amountMetres == 200)
    }

    @Test func goalsOfStampsFinishWithTheRecordsOfTheWeek() {
        let street = Street.ID(area: 243, name: "Bahnhofstrasse")
        let records = GoalRecords(
            streets: [CompletedRecord(dog: dog, goal: street, date: time(day: 2))],
            steps: [
                CompletedRecord(dog: dog, goal: AreaStepID(area: 242, step: .entry), date: time(day: 1, week: -1)),
                CompletedRecord(dog: dog, goal: AreaStepID(area: 247, step: .entry), date: time(day: 3)),
                CompletedRecord(dog: dog, goal: AreaStepID(area: 243, step: .half), date: time(day: 4)),
            ],
            rings: [CompletedRecord(dog: dog, goal: Ring(number: 2, centre: HomeBase(latitude: 47.4, longitude: 8.4)), date: time(day: 5))])
        let events = events(records: records)

        #expect(WeeklyGoals.progress(of: .street(street), in: events).finishedAt == time(day: 2))
        #expect(WeeklyGoals.progress(of: .street(nil), in: events).finishedAt == time(day: 2))
        #expect(WeeklyGoals.progress(of: .street(Street.ID(area: 243, name: "Kirchweg")), in: events).finishedAt == nil)
        #expect(WeeklyGoals.progress(of: .newArea, in: events).finishedAt == time(day: 3))
        #expect(WeeklyGoals.progress(of: .areaStep(AreaStepID(area: 243, step: .quarter)), in: events).finishedAt == time(day: 4))
        #expect(WeeklyGoals.progress(of: .areaStep(AreaStepID(area: 243, step: .threeQuarters)), in: events).finishedAt == nil)
        #expect(WeeklyGoals.progress(of: .ring(2), in: events).finishedAt == time(day: 5))
        #expect(WeeklyGoals.progress(of: .ring(3), in: events).finishedAt == nil)
    }

    // MARK: The goals of a week

    /// A walk of 10 km in each of the four weeks before the week, which
    /// collects 1 km of new segments and refreshes 2 km of old marks.
    private func usualWeeks(weeks: [Int] = [-1, -2, -3, -4]) -> (walks: [GoalWalk], collection: DogCollection) {
        var segments: [(Segment.ID, CollectedSegment)] = []
        var walks: [GoalWalk] = []
        for offset in weeks {
            for index in 0..<2 {
                let old = "old-\(offset)-\(index)"
                segments.append(collected(old, metres: 1_000, at: time(day: 0, week: offset - 6)))
                segments.append(collected("new-\(offset)-\(index)", metres: 500, at: time(day: 2, hour: 9.5, week: offset)))
                walks.append(walk(day: 2 + index, week: offset, metres: 5_000, marks: [old: 10]))
            }
        }
        return (walks, collection(segments))
    }

    private func goals(
        for dog: UUID? = nil, walks: [GoalWalk], collection: DogCollection = DogCollection(), nearGoals: [NearGoal] = []
    ) -> [WeeklyGoal] {
        WeeklyGoals.goals(for: dog ?? self.dog, week: week, collection: collection, walks: walks, nearGoals: nearGoals)
    }

    @Test func aDogWithoutAnEarlierWalkGetsTheStarterGoals() {
        #expect(goals(walks: []) == [.distance(metres: 1_000), .street(nil), .ring(1)])
        #expect(goals(walks: [walk(day: 0)]) == [.distance(metres: 1_000), .street(nil), .ring(1)])
    }

    @Test func theAverageWeekComesFromTheFourWeeksBefore() {
        let (walks, collection) = usualWeeks()
        let average = WeeklyGoals.averageWeek(before: week, collection: collection, walks: walks)
        #expect(average == AverageWeek(newMetres: 1_000, walkedMetres: 10_000, refreshedMetres: 2_000))
    }

    /// A holiday week without any walk does not make the goals smaller.
    @Test func theAverageWeekCountsOnlyTheWeeksWithWalks() {
        let (walks, collection) = usualWeeks(weeks: [-1, -3])
        let earlier = walk(day: 3, week: -5, metres: 50_000)
        let average = WeeklyGoals.averageWeek(before: week, collection: collection, walks: walks + [earlier])
        #expect(average == AverageWeek(newMetres: 1_000, walkedMetres: 10_000, refreshedMetres: 2_000))
    }

    /// The easy goal fits the usual round, the middle goal needs a small
    /// detour, and the hard goal a longer walk or a trip.
    @Test func theGoalsAreSizedFromTheAverageWeek() {
        let (walks, collection) = usualWeeks()
        var chosen: [Set<WeeklyGoal>] = Array(repeating: [], count: 3)
        for _ in 0..<40 {
            for (slot, goal) in goals(for: UUID(), walks: walks, collection: collection).enumerated() {
                chosen[slot].insert(goal)
            }
        }
        #expect(chosen[0] == [.distance(metres: 5_000), .refresh(metres: 1_000)])
        #expect(chosen[1] == [.newLength(metres: 1_000)])
        #expect(chosen[2] == [.distance(metres: 15_000), .newLength(metres: 2_000), .newArea])
    }

    @Test func theMiddleGoalCanBeAStreetOrAStepCloseToTheHomeBase() {
        let (walks, collection) = usualWeeks()
        let street = WeeklyGoal.street(Street.ID(area: 243, name: "Kirchweg"))
        let near = [
            NearGoal(goal: street, missingMetres: 400),
            NearGoal(goal: .ring(3), missingMetres: 900),
            NearGoal(goal: .areaStep(AreaStepID(area: 243, step: .half)), missingMetres: 9_000),
        ]
        var chosen: Set<WeeklyGoal> = []
        for _ in 0..<40 {
            chosen.insert(goals(for: UUID(), walks: walks, collection: collection, nearGoals: near)[1])
        }
        #expect(chosen == [.newLength(metres: 1_000), street, .ring(3)])
    }

    @Test func aDogGetsTheSameGoalsForTheSameWeek() {
        let (walks, collection) = usualWeeks()
        let first = goals(walks: walks, collection: collection)
        #expect(goals(walks: walks, collection: collection) == first)
    }

    /// A dog that has not walked for a month gets small goals.
    @Test func aDogWithoutRecentWalksGetsTheSmallestGoals() {
        let goals = goals(for: UUID(), walks: [walk(day: 0, week: -8, metres: 40_000)])
        #expect(goals[0] == .distance(metres: 1_000))
        #expect([.newLength(metres: 200)].contains(goals[1]))
        #expect([.distance(metres: 3_000), .newLength(metres: 500), .newArea].contains(goals[2]))
    }

    // MARK: The swap

    private func set(_ goals: [WeeklyGoal], finished: [Date?] = [nil, nil, nil]) -> WeeklyGoalSet {
        WeeklyGoalSet(
            dog: dog, weekStart: week.start,
            slots: zip(goals, finished).map { GoalSlot(goal: $0, finishedAt: $1) }, swappedSlot: nil)
    }

    @Test func aMemberSwapsOneGoalForAnotherOfTheSameSize() throws {
        let (walks, collection) = usualWeeks()
        let goals: [WeeklyGoal] = [.distance(metres: 5_000), .newLength(metres: 1_000), .newArea]
        let swapped = try #require(WeeklyGoals.swap(
            slot: 2, of: set(goals), collection: collection, walks: walks, nearGoals: []))

        #expect(swapped.swappedSlot == 2)
        #expect(Array(swapped.slots.map(\.goal).prefix(2)) == Array(goals.prefix(2)))
        #expect([.distance(metres: 15_000), .newLength(metres: 2_000)].contains(swapped.slots[2].goal))
    }

    @Test func aSetHasOneSwapOnly() throws {
        let (walks, collection) = usualWeeks()
        let goals: [WeeklyGoal] = [.distance(metres: 5_000), .newLength(metres: 1_000), .newArea]
        let swapped = try #require(WeeklyGoals.swap(
            slot: 0, of: set(goals), collection: collection, walks: walks, nearGoals: []))

        #expect(WeeklyGoals.swap(slot: 2, of: swapped, collection: collection, walks: walks, nearGoals: []) == nil)
        #expect(WeeklyGoals.swap(slot: 0, of: swapped, collection: collection, walks: walks, nearGoals: []) == nil)
    }

    @Test func aFinishedGoalCannotBeSwapped() {
        let (walks, collection) = usualWeeks()
        let finished = set([.distance(metres: 5_000), .newLength(metres: 1_000), .newArea], finished: [time(day: 1), nil, nil])
        #expect(WeeklyGoals.swap(slot: 0, of: finished, collection: collection, walks: walks, nearGoals: []) == nil)
    }

    @Test func aStarterGoalSwapsForAnotherStarterGoal() throws {
        let swapped = try #require(WeeklyGoals.swap(
            slot: 2, of: set(WeeklyGoals.starterGoals), collection: DogCollection(), walks: [], nearGoals: []))
        #expect(swapped.slots[2].goal == .newArea)
    }

    // MARK: The week stamp and the streak

    private func finishedSet(week offset: Int, count: Int) -> WeeklyGoalSet {
        WeeklyGoalSet(
            dog: dog, weekStart: WeekCalendar.weekStart(week.start, movedBy: offset),
            slots: (0..<3).map { GoalSlot(goal: .newArea, finishedAt: $0 < count ? time(day: $0, week: offset) : nil) },
            swappedSlot: nil)
    }

    @Test func threeFinishedGoalsGiveAWeekStamp() {
        #expect(finishedSet(week: 0, count: 3).hasWeekStamp)
        #expect(finishedSet(week: 0, count: 3).weekStampDate == time(day: 2))
        #expect(!finishedSet(week: 0, count: 2).hasWeekStamp)
    }

    @Test func theStreakCountsTheWeeksInARowWithAFinishedGoal() {
        let sets = [finishedSet(week: -1, count: 1), finishedSet(week: -2, count: 3), finishedSet(week: -3, count: 2)]
        let walks = [-1, -2, -3].map { walk(day: 1, week: $0) }
        #expect(WeeklyGoals.streak(of: sets, walks: walks, now: time(day: 0, hour: 7)) == 3)
    }

    @Test func aWeekWithWalksAndNoFinishedGoalEndsTheStreak() {
        let sets = [finishedSet(week: -1, count: 1), finishedSet(week: -2, count: 0), finishedSet(week: -3, count: 2)]
        let walks = [-1, -2, -3].map { walk(day: 1, week: $0) }
        #expect(WeeklyGoals.streak(of: sets, walks: walks, now: time(day: 0, hour: 7)) == 1)
    }

    /// A holiday without the dog does not end the streak.
    @Test func aWeekWithoutAWalkPausesTheStreak() {
        let sets = [finishedSet(week: -1, count: 1), finishedSet(week: -2, count: 0), finishedSet(week: -3, count: 2)]
        let walks = [-1, -3].map { walk(day: 1, week: $0) }
        #expect(WeeklyGoals.streak(of: sets, walks: walks, now: time(day: 0, hour: 7)) == 2)
    }

    @Test func theCurrentWeekCountsAsSoonAsItHasAFinishedGoalAndNeverEndsTheStreak() {
        let walks = [-1, 0].map { walk(day: 1, week: $0) }
        let before = [finishedSet(week: -1, count: 1), finishedSet(week: 0, count: 0)]
        #expect(WeeklyGoals.streak(of: before, walks: walks, now: time(day: 3)) == 1)
        let after = [finishedSet(week: -1, count: 1), finishedSet(week: 0, count: 1)]
        #expect(WeeklyGoals.streak(of: after, walks: walks, now: time(day: 3)) == 2)
    }

    @Test func aDogWithoutFinishedGoalsHasNoStreak() {
        #expect(WeeklyGoals.streak(of: [], walks: [walk(day: 1, week: -1)], now: time(day: 3)) == 0)
        #expect(WeeklyGoals.streak(of: [], walks: [], now: time(day: 3)) == 0)
    }

    // MARK: The year page

    @Test func theYearPageMarksEachWeek() throws {
        let sets = [finishedSet(week: -3, count: 3), finishedSet(week: -2, count: 1), finishedSet(week: 0, count: 2)]
        let walks = [-4, -3, -2, 0].map { walk(day: 1, week: $0) }
        let weeks = WeeklyGoals.weeks(ofYear: 2026, sets: sets, walks: walks, now: time(day: 3))

        #expect(weeks.count == 53)
        func mark(_ offset: Int) -> WeekMark? {
            weeks.first { $0.weekStart == WeekCalendar.weekStart(week.start, movedBy: offset) }?.mark
        }
        #expect(mark(-5) == WeekMark.none)
        #expect(mark(-4) == WeekMark.none)
        #expect(mark(-3) == .weekStamp)
        #expect(mark(-2) == .finishedGoals)
        #expect(mark(-1) == .paused)
        #expect(mark(0) == .finishedGoals)
        #expect(mark(1) == WeekMark.none)
    }
}
