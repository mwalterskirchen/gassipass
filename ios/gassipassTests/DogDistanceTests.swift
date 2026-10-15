//
//  DogDistanceTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 15.10.2026.
//

import Foundation
import Testing
@testable import gassipass

struct DogDistanceTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func walk(
        _ start: Date, minutes: Double = 60, metres: Double = 1000, id: UUID = UUID()
    ) -> (id: UUID, startedAt: Date, endedAt: Date, distanceMetres: Double) {
        (id: id, startedAt: start, endedAt: start.addingTimeInterval(minutes * 60), distanceMetres: metres)
    }

    private func isAbout(_ metres: Double, _ expected: Double) -> Bool {
        abs(metres - expected) < 0.001
    }

    private func isAbout(_ metres: [Double], _ expected: [Double]) -> Bool {
        metres.count == expected.count && zip(metres, expected).allSatisfy(isAbout)
    }

    @Test func walksThatDoNotOverlapAddUp() {
        let distance = DogDistance(walks: [walk(date(10, 12, 9), metres: 3000), walk(date(10, 12, 17), metres: 2000)])
        #expect(distance.totalMetres == 5000)
    }

    /// Two members walk the dog at the same time. In the half hour in which
    /// the walks overlap, only the faster walk counts.
    @Test func theTimeInWhichTwoWalksOverlapCountsOnceAsTheFasterWalk() {
        let first = walk(date(10, 12, 10), metres: 4000)
        let second = walk(date(10, 12, 10, 30), metres: 5000)
        let distance = DogDistance(walks: [second, first])

        #expect(distance.walks.map(\.id) == [first.id, second.id])
        #expect(isAbout(distance.walks.map(\.countedMetres), [2000, 5000]))
        #expect(isAbout(distance.totalMetres, 7000))
    }

    /// A member forgot to stop a walk, which ran for 13 hours with 3 km.
    /// The walk of another member in that time is faster, so it counts.
    @Test func aFasterWalkInsideASlowWalkCounts() {
        let forgotten = walk(date(10, 12, 9), minutes: 13 * 60, metres: 3000)
        let evening = walk(date(10, 12, 18), metres: 5000)
        let distance = DogDistance(walks: [forgotten, evening])

        #expect(isAbout(distance.walks.map(\.countedMetres), [3000 * 12 / 13, 5000]))
    }

    @Test func aSlowerWalkInsideAFasterWalkCountsNothing() {
        let distance = DogDistance(walks: [
            walk(date(10, 12, 10), minutes: 120, metres: 4000), walk(date(10, 12, 10, 30), minutes: 30, metres: 500),
        ])
        #expect(isAbout(distance.walks.map(\.countedMetres), [4000, 0]))
    }

    /// Two members walk the dog together, so the dog went on one walk. The
    /// walk that counts nothing is not in the bar of the day.
    @Test func twoWalksAtTheSameTimeAreOneWalkInTheBar() {
        let distance = DogDistance(walks: [walk(date(10, 12, 10), metres: 3000), walk(date(10, 12, 10), metres: 3000)])
        let page = distance.page(.day, containing: date(10, 12, 12), now: date(10, 15, 12), calendar: calendar)

        #expect(isAbout(distance.totalMetres, 3000))
        #expect(page.bars.first?.walkMetres.count == 1)
        #expect(page.walkCount == 1)
    }

    @Test func theLongestAndTheAverageWalkUseTheDistanceOfTheWalkItself() {
        let distance = DogDistance(walks: [walk(date(10, 12, 10), metres: 5000), walk(date(10, 12, 10, 30), metres: 4000)])
        #expect(distance.longestWalk?.distanceMetres == 5000)
        #expect(distance.averageWalkMetres == 4500)
    }

    @Test func aDogWithNoWalksHasNoDistance() {
        let distance = DogDistance(walks: [])
        let page = distance.page(.day, containing: date(10, 15, 12), now: date(10, 15, 12), calendar: calendar)

        #expect(distance.totalMetres == 0)
        #expect(distance.longestWalk == nil)
        #expect(distance.averageWalkMetres == nil)
        #expect(page.metres == 0)
        #expect(page.averageMetres == nil)
        #expect(!page.hasEarlier)
    }

    /// The week of Wednesday 15 October 2026 starts on Monday 12 October.
    @Test func aPageOfDaysIsTheWeekWithEachWalkOfADay() {
        let distance = DogDistance(walks: [
            walk(date(10, 12, 8), metres: 2000), walk(date(10, 12, 18), metres: 3000),
            walk(date(10, 14, 9), metres: 1500), walk(date(10, 11, 9), metres: 9000),
        ])
        let page = distance.page(.day, containing: date(10, 15, 12), now: date(10, 15, 12), calendar: calendar)

        #expect(page.bars.count == 7)
        #expect(page.bars.first?.interval.start == date(10, 12, 0))
        #expect(page.bars.map(\.walkMetres) == [[2000, 3000], [], [1500], [], [], [], []])
        #expect(page.metres == 6500)
        #expect(page.walkCount == 3)
        #expect(page.hasEarlier)
        #expect(!page.hasLater)
    }

    @Test func aWalkCountsInTheDayInWhichItStarted() {
        let distance = DogDistance(walks: [walk(date(10, 12, 23, 30))])
        let page = distance.page(.day, containing: date(10, 12, 12), now: date(10, 15, 12), calendar: calendar)
        #expect(page.bars.map(\.metres) == [1000, 0, 0, 0, 0, 0, 0])
    }

    /// The first walk is on Tuesday and now is Thursday, so the average
    /// counts Tuesday and Wednesday.
    @Test func theAverageCountsTheDaysFromTheFirstWalkThatAreOver() {
        let distance = DogDistance(walks: [walk(date(10, 13, 9), metres: 3000), walk(date(10, 15, 9), metres: 3000)])
        let page = distance.page(.day, containing: date(10, 15, 12), now: date(10, 15, 12), calendar: calendar)
        #expect(page.averageMetres == 1500)
    }

    /// The month has only begun, so the average of the year counts only
    /// September.
    @Test func theAverageLeavesOutTheMonthThatHasOnlyBegun() {
        let distance = DogDistance(walks: [walk(date(9, 1, 9), metres: 90_000), walk(date(10, 1, 9), metres: 3000)])
        let page = distance.page(.month, containing: date(10, 2, 12), now: date(10, 2, 12), calendar: calendar)
        #expect(page.averageMetres == 90_000)
    }

    @Test func whileNoDayIsOverTheAverageCountsTheCurrentDayOnceItHasAWalk() {
        let today = DogDistance(walks: [walk(date(10, 15, 9), metres: 3000)])
        #expect(today.page(.day, containing: date(10, 15, 12), now: date(10, 15, 12), calendar: calendar)
            .averageMetres == 3000)

        let lastWeek = DogDistance(walks: [walk(date(10, 8, 9), metres: 3000)])
        #expect(lastWeek.page(.day, containing: date(10, 12, 7), now: date(10, 12, 7), calendar: calendar)
            .averageMetres == nil)
    }

    @Test func aPageOfWeeksEndsWithTheWeekOfTheDate() {
        let distance = DogDistance(walks: [walk(date(7, 20, 9)), walk(date(10, 14, 9)), walk(date(10, 15, 9))])
        let page = distance.page(.week, containing: date(10, 15, 12), now: date(10, 15, 12), calendar: calendar)

        #expect(page.bars.count == 12)
        #expect(page.bars.first?.interval.start == date(7, 27, 0))
        #expect(page.bars.last?.interval.start == date(10, 12, 0))
        #expect(page.bars.last?.metres == 2000)
        #expect(page.metres == 2000)
        #expect(page.hasEarlier)
    }

    @Test func aPageOfMonthsIsTheYear() {
        let distance = DogDistance(walks: [walk(date(1, 3, 9)), walk(date(10, 14, 9)), walk(date(12, 31, 9, year: 2025))])
        let page = distance.page(.month, containing: date(10, 15, 12), now: date(10, 15, 12), calendar: calendar)

        #expect(page.bars.count == 12)
        #expect(page.bars.map(\.metres) == [1000, 0, 0, 0, 0, 0, 0, 0, 0, 1000, 0, 0])
        #expect(page.hasEarlier)
        #expect(!page.hasLater)
    }

    /// Two walks of a day, the second so short that it still shows.
    @Test func theWalksOfABarStackWithAGapAndAMinimumHeight() {
        let pieces = StackedBar.pieces(of: [10, 0, 0.1], gap: 1, minimum: 0.5)
        #expect(pieces == [0...9.5, 10.5...11])
    }

    @Test func anEarlierPageHasALaterPage() {
        let distance = DogDistance(walks: [walk(date(10, 1, 9))])
        let earlier = DistanceUnit.week.date(date(10, 15, 12), movedBy: -1, calendar: calendar)
        let page = distance.page(.week, containing: earlier, now: date(10, 15, 12), calendar: calendar)

        #expect(page.interval.end == date(7, 27, 0))
        #expect(page.hasLater)
        #expect(!page.hasEarlier)
    }
}
