//
//  GoalChoice.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation

/// What a dog did in an average week of the four weeks before a week.
public nonisolated struct AverageWeek: Equatable, Sendable {
    public var newMetres: Double
    public var refreshedMetres: Double

    /// The average week of a dog that has walked before, but not in the
    /// four weeks before the week. Its goals get the smallest sizes.
    public static let quiet = AverageWeek(newMetres: 0, refreshedMetres: 0)

    public init(newMetres: Double, refreshedMetres: Double) {
        self.newMetres = newMetres
        self.refreshedMetres = refreshedMetres
    }
}

/// A goal near the home base that a stamp finishes: a street that the dog
/// has not completed, the next step of the area of the home base, or the
/// current ring, with the length that the dog still has to collect for it.
public nonisolated struct NearGoal: Equatable, Sendable {
    public let goal: WeeklyGoal
    public let missingMetres: Double

    public init(goal: WeeklyGoal, missingMetres: Double) {
        self.goal = goal
        self.missingMetres = missingMetres
    }
}

/// The sizes of the weekly goals, as shares of an average week. We tune
/// them with the replay tool (`GoalReplay`).
public nonisolated enum GoalSizes {
    /// The easy goal asks for about half an average week, of a kind that
    /// fits the usual round.
    public static let easyShare = 0.5
    /// The middle goal asks for about one average week of new segments.
    public static let middleShare = 1.0
    /// The hard goal asks for more new segments.
    public static let hardNewShare = 2.0
    /// A street or a step close to the home base is a middle goal when the
    /// dog has to collect at most this share of an average week for it.
    public static let nearShare = 1.5
    /// An easy goal of refreshed marks needs an average week with at least
    /// this length of refreshed marks.
    public static let refreshMinimumMetres = 400.0
    /// An easy goal of new segments needs an average week with at least
    /// this length of new segments. A dog that neither refreshes nor
    /// collects that much gets the smallest goal of new segments.
    public static let easyNewMinimumMetres = 400.0

    public static let refreshMinimumTargetMetres = 300.0
    public static let easyNewMinimumTargetMetres = 100.0
    public static let middleNewMinimumMetres = 200.0
    public static let hardNewMinimumMetres = 500.0
    /// A near goal fits a dog that collects little, as if the average week
    /// had this much new length.
    public static let nearMinimumMetres = 300.0
    /// The number of near streets that can be a middle goal, and of far
    /// streets that can be a hard goal.
    public static let nearStreetCount = 3

    /// A length of segments rounded to 100 m, so that the goals read well.
    public static func length(_ metres: Double, minimum: Double) -> Double {
        max(minimum, (metres / 100).rounded() * 100)
    }
}

nonisolated extension WeeklyGoals {
    /// The goals of a dog in its first week: collect 1 km of new segments,
    /// complete any street, and complete ring 1.
    public static let starterGoals: [WeeklyGoal] = [.newLength(metres: 1_000), .street(nil), .ring(1)]

    /// The goals that a starter goal can be swapped for, by slot.
    private static let starterSwaps: [[WeeklyGoal]] = [
        [.newLength(metres: 1_000)], [.newArea], [.newArea],
    ]

    /// The three goals of the dog for the week: the starter goals for a dog
    /// without a walk before the week, or else goals sized from the average
    /// week. The same dog, week and walks always give the same goals.
    ///
    /// - Parameters:
    ///   - walks: The ended walks of the dog, at least those of the six
    ///     weeks before the week.
    ///   - nearGoals: The goals near the home base, the nearest first.
    ///   - farStreets: The streets far from the usual rounds that the dog
    ///     has not completed, in the areas that it has entered.
    public static func goals(
        for dog: UUID, week: DateInterval, collection: DogCollection, walks: [GoalWalk], nearGoals: [NearGoal],
        farStreets: [NearGoal] = []
    ) -> [WeeklyGoal] {
        guard hasWalked(before: week, walks) else { return starterGoals }
        return candidates(
            week: week, collection: collection, walks: walks, nearGoals: nearGoals, farStreets: farStreets)
            .enumerated()
            .map { slot, options in choose(from: options, dog: dog, week: week, salt: slot) }
    }

    /// The set with another goal of the same size in the slot, or nil when
    /// the set has had its swap, the goal of the slot is finished, or no
    /// other goal fits.
    public static func swap(
        slot: Int, of set: WeeklyGoalSet, collection: DogCollection, walks: [GoalWalk], nearGoals: [NearGoal],
        farStreets: [NearGoal] = []
    ) -> WeeklyGoalSet? {
        guard set.swappedSlot == nil, set.slots.indices.contains(slot), set.slots[slot].finishedAt == nil
        else { return nil }
        let week = set.week
        let options = hasWalked(before: week, walks)
            ? candidates(
                week: week, collection: collection, walks: walks, nearGoals: nearGoals, farStreets: farStreets)[slot]
            : starterSwaps[slot]
        let goals = set.slots.map(\.goal)
        let others = options.filter { !goals.contains($0) }
        guard !others.isEmpty else { return nil }
        var swapped = set
        swapped.slots[slot] = GoalSlot(
            goal: choose(from: others, dog: set.dog, week: week, salt: WeeklyGoalSet.slotCount + slot), finishedAt: nil)
        swapped.swappedSlot = slot
        return swapped
    }

    /// The average week of the four weeks before the week, from the weeks
    /// in which the dog walked, or nil when it did not walk in them. A week
    /// without a walk, for example a holiday, does not make it smaller.
    public static func averageWeek(before week: DateInterval, collection: DogCollection, walks: [GoalWalk]) -> AverageWeek? {
        let weeks = (1...4).map { WeekCalendar.week(startingAt: WeekCalendar.weekStart(week.start, movedBy: -$0)) }
            .filter { week in walks.contains { week.holds($0.startedAt) } }
        guard !weeks.isEmpty else { return nil }
        var sum = AverageWeek.quiet
        for week in weeks {
            let events = GoalEvents(week: week, collection: collection, walks: walks, records: GoalRecords())
            sum.newMetres += events.newSegments.reduce(0) { $0 + $1.metres }
            sum.refreshedMetres += events.refreshed.reduce(0) { $0 + $1.metres }
        }
        let count = Double(weeks.count)
        return AverageWeek(newMetres: sum.newMetres / count, refreshedMetres: sum.refreshedMetres / count)
    }

    private static func hasWalked(before week: DateInterval, _ walks: [GoalWalk]) -> Bool {
        walks.contains { $0.startedAt < week.start }
    }

    /// The goals that fit each slot: the easy, the middle and the hard one.
    private static func candidates(
        week: DateInterval, collection: DogCollection, walks: [GoalWalk], nearGoals: [NearGoal],
        farStreets: [NearGoal]
    ) -> [[WeeklyGoal]] {
        let average = averageWeek(before: week, collection: collection, walks: walks) ?? .quiet
        var easy: [WeeklyGoal] = []
        if average.refreshedMetres >= GoalSizes.refreshMinimumMetres {
            easy.append(.refresh(metres: GoalSizes.length(
                average.refreshedMetres * GoalSizes.easyShare, minimum: GoalSizes.refreshMinimumTargetMetres)))
        }
        if average.newMetres >= GoalSizes.easyNewMinimumMetres || easy.isEmpty {
            easy.append(.newLength(metres: GoalSizes.length(
                average.newMetres * GoalSizes.easyShare, minimum: GoalSizes.easyNewMinimumTargetMetres)))
        }
        let nearLimit = max(average.newMetres, GoalSizes.nearMinimumMetres) * GoalSizes.nearShare
        let near = nearGoals.filter { $0.missingMetres <= nearLimit }
        let nearStreets = near.filter { if case .street = $0.goal { true } else { false } }
            .prefix(GoalSizes.nearStreetCount)
        let nearSteps = near.filter { if case .street = $0.goal { false } else { true } }
        let middle: [WeeklyGoal] = [.newLength(metres: GoalSizes.length(
            average.newMetres * GoalSizes.middleShare, minimum: GoalSizes.middleNewMinimumMetres))]
            + nearStreets.map(\.goal) + nearSteps.map(\.goal)
        let farLimit = max(average.newMetres, GoalSizes.nearMinimumMetres) * GoalSizes.hardNewShare
        let hard: [WeeklyGoal] = [
            .newLength(metres: GoalSizes.length(
                average.newMetres * GoalSizes.hardNewShare, minimum: GoalSizes.hardNewMinimumMetres)),
            .newArea,
        ] + farStreets.filter { $0.missingMetres <= farLimit }.prefix(GoalSizes.nearStreetCount).map(\.goal)
        return [easy, middle, hard]
    }

    /// One of the goals, the same one for the same dog, week and salt on
    /// every phone. The choice gives each of the goals about the same
    /// chance.
    private static func choose(from goals: [WeeklyGoal], dog: UUID, week: DateInterval, salt: Int) -> WeeklyGoal {
        // FNV-1a, because the hash of Swift changes with each launch.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(dog.uuidString)|\(WeekCalendar.dayText(of: week.start))|\(salt)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return goals[Int(hash % UInt64(goals.count))]
    }
}
