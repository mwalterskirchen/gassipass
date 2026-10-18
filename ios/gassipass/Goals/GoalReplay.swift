//
//  GoalReplay.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation

/// Replays the last 12 weeks of a dog through the rules of the weekly
/// goals, with the walks as they happened: for each week, the goals that
/// the app would have made at its start, and when the dog would have
/// finished each one. We use it on the walks of our pack to tune the sizes
/// (`GoalSizes`) before the release.
///
/// The goals near the home base are those of today, because the app does
/// not know the map of an earlier week.
nonisolated enum GoalReplay {
    static let weekCount = 12

    struct Week: Equatable, Sendable {
        let weekStart: Date
        let goals: [WeeklyGoal]
        /// The time at which the dog would have finished each goal, or nil.
        let finishedAt: [Date?]
    }

    /// The last 12 weeks that have ended, the oldest first.
    static func weeks(
        of dog: UUID, collection: DogCollection, walks: [GoalWalk], records: GoalRecords, nearGoals: [NearGoal],
        now: Date
    ) -> [Week] {
        let current = WeekCalendar.week(containing: now).start
        return (1...weekCount).reversed().map { offset in
            let week = WeekCalendar.week(startingAt: WeekCalendar.weekStart(current, movedBy: -offset))
            let goals = WeeklyGoals.goals(
                for: dog, week: week, collection: collection, walks: walks.filter { $0.startedAt < week.start },
                nearGoals: nearGoals)
            let events = GoalEvents(week: week, collection: collection, walks: walks, records: records)
            return Week(
                weekStart: week.start, goals: goals,
                finishedAt: goals.map { WeeklyGoals.progress(of: $0, in: events).finishedAt })
        }
    }

    /// The report of the weeks as text, one line for each goal.
    static func report(_ weeks: [Week], title: (WeeklyGoal) -> String) -> String {
        weeks.map { week in
            let finished = week.finishedAt.count { $0 != nil }
            let lines = zip(week.goals, week.finishedAt).map { goal, finishedAt in
                "  \(finishedAt == nil ? "–" : "✓") \(title(goal))"
            }
            return (["\(WeekCalendar.dayText(of: week.weekStart)): \(finished) of \(week.goals.count)"] + lines)
                .joined(separator: "\n")
        }
        .joined(separator: "\n")
    }
}
