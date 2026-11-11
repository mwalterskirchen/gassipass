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

/// A week stamp of a dog: the week and the date of the stamp.
public nonisolated struct WeekStamp: Equatable, Sendable, Identifiable {
    public let weekStart: Date
    public let date: Date

    public var id: Date { weekStart }
}

nonisolated extension WeeklyGoals {
    /// The years of the year pages of a dog, the newest first: from the
    /// year of its first walk or set of weekly goals to this year. A dog
    /// without either has this year only.
    public static func years(from first: Date?, to now: Date) -> [Int] {
        let from = year(of: first ?? now)
        return Array((from...max(from, year(of: now))).reversed())
    }

    /// The number of week stamps in the sets of the year.
    public static func weekStampCount(in sets: [WeeklyGoalSet], year: Int) -> Int {
        sets.count { $0.hasWeekStamp && self.year(of: $0.weekStart) == year }
    }

    /// The week stamps in the sets of the weeks, the earliest week first.
    public static func weekStamps(in sets: [WeeklyGoalSet], of weeks: [YearWeek]) -> [WeekStamp] {
        sets
            .filter { set in weeks.contains { $0.weekStart.isSameMillisecond(as: set.weekStart) } }
            .compactMap { set in set.weekStampDate.map { WeekStamp(weekStart: set.weekStart, date: $0) } }
            .sorted { $0.weekStart < $1.weekStart }
    }

    /// The year of the week of the date, by the week numbers of
    /// `WeekCalendar`.
    private static func year(of date: Date) -> Int {
        WeekCalendar.calendar.component(.yearForWeekOfYear, from: date)
    }
}
