//
//  WeekCalendarTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import Testing
@testable import gassipass

struct WeekCalendarTests {
    /// A time in Zurich, with the offset of summer (+02:00) or winter
    /// (+01:00) time.
    private func zurich(_ text: String) -> Date {
        try! Date(text, strategy: .iso8601)
    }

    @Test func aWeekStartsOnMondayAtMidnightInZurich() {
        let week = WeekCalendar.week(containing: zurich("2026-10-15T12:00:00+02:00"))
        #expect(week.start == zurich("2026-10-12T00:00:00+02:00"))
        #expect(week.end == zurich("2026-10-19T00:00:00+02:00"))
    }

    @Test func sundayLateAtNightIsStillInTheWeek() {
        let week = WeekCalendar.week(containing: zurich("2026-10-18T23:59:00+02:00"))
        #expect(week.start == zurich("2026-10-12T00:00:00+02:00"))
    }

    /// Midnight in Zurich is 22:00 UTC on Sunday in summer time.
    @Test func mondayAtMidnightInZurichStartsTheNextWeek() {
        let week = WeekCalendar.week(containing: zurich("2026-10-18T22:00:00Z"))
        #expect(week.start == zurich("2026-10-19T00:00:00+02:00"))
    }

    /// Summer time ends on Sunday, 25 October 2026, so that week has 169
    /// hours.
    @Test func theWeekOfTheEndOfSummerTimeHasAnHourMore() {
        let week = WeekCalendar.week(containing: zurich("2026-10-25T12:00:00+01:00"))
        #expect(week.start == zurich("2026-10-19T00:00:00+02:00"))
        #expect(week.end == zurich("2026-10-26T00:00:00+01:00"))
        #expect(week.duration == 169 * 3_600)
    }

    /// Summer time starts on Sunday, 29 March 2026, so that week has 167
    /// hours.
    @Test func theWeekOfTheStartOfSummerTimeHasAnHourLess() {
        let week = WeekCalendar.week(containing: zurich("2026-03-30T00:30:00+02:00"))
        #expect(week.start == zurich("2026-03-30T00:00:00+02:00"))
        let before = WeekCalendar.week(containing: zurich("2026-03-29T12:00:00+02:00"))
        #expect(before.start == zurich("2026-03-23T00:00:00+01:00"))
        #expect(before.duration == 167 * 3_600)
    }

    @Test func theDayOfAWeekStartIsTheMondayInZurich() {
        let start = zurich("2026-10-19T00:00:00+02:00")
        #expect(WeekCalendar.dayText(of: start) == "2026-10-19")
        #expect(WeekCalendar.date(ofDayText: "2026-10-19") == start)
    }

    @Test func weeksMoveByWholeWeeksAcrossTheChangeOfTime() {
        let start = zurich("2026-10-19T00:00:00+02:00")
        #expect(WeekCalendar.weekStart(start, movedBy: 1) == zurich("2026-10-26T00:00:00+01:00"))
        #expect(WeekCalendar.weekStart(start, movedBy: -1) == zurich("2026-10-12T00:00:00+02:00"))
    }
}
