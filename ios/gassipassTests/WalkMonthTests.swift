//
//  WalkMonthTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 12.10.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

@MainActor
struct WalkMonthTests {
    let container: ModelContainer
    let bello: Dog
    var calendar = Calendar(identifier: .gregorian)

    init() throws {
        container = try LocalStore.inMemory()
        bello = Dog(name: "Bello", context: container.mainContext)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    }

    private func walk(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9, metres: Double = 1000) -> Walk {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        let walk = Walk(startedAt: date, dogs: [bello], context: container.mainContext)
        walk.distanceMetres = metres
        return walk
    }

    @Test func walksOfTheSameMonthShareASection() {
        let walks = [walk(2026, 10, 12), walk(2026, 10, 1, hour: 0), walk(2026, 9, 30, hour: 23), walk(2025, 9, 30)]
        let months = WalkMonth.grouping(walks, calendar: calendar)
        #expect(months.map(\.walks.count) == [2, 1, 1])
        #expect(months.map { calendar.dateComponents([.year, .month], from: $0.start) }
            == [DateComponents(year: 2026, month: 10), DateComponents(year: 2026, month: 9), DateComponents(year: 2025, month: 9)])
    }

    @Test func theWalksKeepTheirOrder() {
        let walks = [walk(2026, 10, 12), walk(2026, 10, 3), walk(2026, 10, 7)]
        #expect(WalkMonth.grouping(walks, calendar: calendar).first?.walks.map(\.id) == walks.map(\.id))
    }

    @Test func theDistanceOfAMonthIsTheSumOfItsWalks() {
        let months = WalkMonth.grouping([walk(2026, 10, 12, metres: 1500), walk(2026, 10, 3, metres: 2500)], calendar: calendar)
        #expect(months.first?.distanceMetres == 4000)
    }

    @Test func noWalksGiveNoMonths() {
        #expect(WalkMonth.grouping([], calendar: calendar).isEmpty)
    }
}
