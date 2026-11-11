//
//  YearWeeks.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation

/// How the year page of the passport marks a week.
public nonisolated enum WeekMark: Equatable, Sendable {
    /// The dog finished all three goals.
    case weekStamp
    /// The dog finished one or two goals.
    case finishedGoals
    /// The dog had no walk in the week.
    case noWalk
    /// Nothing: a week before the first walk, a week that has not begun, or
    /// a week with walks and no finished goal.
    case none
}

/// One week of the year page.
public nonisolated struct YearWeek: Equatable, Sendable, Identifiable {
    public let weekStart: Date
    public let mark: WeekMark

    public var id: Date { weekStart }

    public init(weekStart: Date, mark: WeekMark) {
        self.weekStart = weekStart
        self.mark = mark
    }
}

nonisolated extension WeeklyGoals {
    /// The weeks of the year (by the week numbers of `WeekCalendar`) with
    /// their marks, from week 1.
    public static func weeks(ofYear year: Int, sets: [WeeklyGoalSet], walks: [GoalWalk], now: Date) -> [YearWeek] {
        let calendar = WeekCalendar.calendar
        let finished = finishedCounts(of: sets)
        let walked = walkedWeeks(walks)
        let firstWalkedWeek = walked.min()
        guard var week = calendar.date(from: DateComponents(weekday: 2, weekOfYear: 1, yearForWeekOfYear: year))
        else { return [] }
        var weeks: [YearWeek] = []
        while calendar.component(.yearForWeekOfYear, from: week) == year {
            let end = WeekCalendar.weekStart(week, movedBy: 1)
            let mark: WeekMark
            if week > now {
                mark = .none
            } else if (finished[week] ?? 0) == WeeklyGoalSet.slotCount {
                mark = .weekStamp
            } else if (finished[week] ?? 0) > 0 {
                mark = .finishedGoals
            } else if end <= now, !walked.contains(week), let firstWalkedWeek, week > firstWalkedWeek {
                mark = .noWalk
            } else {
                mark = .none
            }
            weeks.append(YearWeek(weekStart: week, mark: mark))
            week = end
        }
        return weeks
    }

    /// The number of finished goals of each week, by the start of the week.
    private static func finishedCounts(of sets: [WeeklyGoalSet]) -> [Date: Int] {
        Dictionary(sets.map { ($0.weekStart, $0.finishedCount) }, uniquingKeysWith: max)
    }

    /// The starts of the weeks in which the dog had an ended walk.
    private static func walkedWeeks(_ walks: [GoalWalk]) -> Set<Date> {
        Set(walks.map { WeekCalendar.week(containing: $0.startedAt).start })
    }
}
