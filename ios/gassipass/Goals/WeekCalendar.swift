//
//  WeekCalendar.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation

/// The one week calendar of the app: a week starts on Monday at midnight in
/// `Europe/Zurich`, on every phone and in every time zone, so that all
/// phones of a pack agree on the week (ADR 0007). The weekly goals, the
/// year page, the Sunday notification and the distance of a dog use it.
nonisolated enum WeekCalendar {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        calendar.locale = Locale(identifier: "de_CH")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    /// The week that contains the date.
    static func week(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)!
    }

    /// The week that starts at the start of a week.
    static func week(startingAt start: Date) -> DateInterval {
        week(containing: start)
    }

    /// The start of the week that is the number of weeks before (negative)
    /// or after the week that starts at the date.
    static func weekStart(_ start: Date, movedBy weeks: Int) -> Date {
        calendar.date(byAdding: .weekOfYear, value: weeks, to: start)!
    }

    /// The day of the date in Zurich, for example "2026-10-19". The server
    /// keeps the start of a week as this day.
    static func dayText(of date: Date) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!)
    }

    /// The midnight in Zurich at the start of the day, or nil for a text
    /// that is no day.
    static func date(ofDayText text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
