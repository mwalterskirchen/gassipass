//
//  DogDistance.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 15.10.2026.
//

import Foundation

/// The distance that one dog walked, from the distances of its walks: in
/// total, and for each day, week or month.
///
/// Two members can walk the same dog at the same time, with one walk each.
/// The total distance counts the time in which the walks overlap only once,
/// as the walk with the highest average speed. That walk counts its distance
/// for that time, and the other walks count nothing for it. The app does not
/// know how far a walk went during the overlap, so the average speed of a
/// walk stands for its speed in that time. Two members who walk the dog
/// together have about the same speed. A walk that a member forgot to stop
/// has a low speed, so it does not hide the walks in its time.
///
/// A walk counts in the day, week or month in which it started, by the
/// calendar of the weekly goals (`WeekCalendar`).
nonisolated struct DogDistance: Equatable, Sendable {
    /// A walk of the dog, with the distance that it adds to the total.
    struct CountedWalk: Equatable, Sendable, Identifiable {
        let id: UUID
        let startedAt: Date
        let endedAt: Date
        /// The distance of the walk itself.
        let distanceMetres: Double
        /// The distance of the walk without the times in which a faster walk
        /// of the dog overlaps it.
        let countedMetres: Double
    }

    typealias RecordedWalk = (id: UUID, startedAt: Date, endedAt: Date, distanceMetres: Double)

    /// The walks, the oldest first.
    let walks: [CountedWalk]

    /// Counts the walks of one dog. The walks can come in any order.
    init(walks: [RecordedWalk]) {
        let sorted = walks
            .map { (id: $0.id, startedAt: $0.startedAt, endedAt: max($0.endedAt, $0.startedAt), distanceMetres: $0.distanceMetres) }
            .sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
        var counted = sorted.map(\.distanceMetres)
        // The walks that overlap one another, one group at a time. A walk
        // that starts when the walks before it have ended starts a new group.
        var group = 0..<0
        var groupEnd = Date.distantPast
        for index in sorted.indices {
            if sorted[index].startedAt >= groupEnd {
                Self.shareOut(sorted[group], into: &counted)
                group = index..<index
            }
            group = group.lowerBound..<index + 1
            groupEnd = max(groupEnd, sorted[index].endedAt)
        }
        Self.shareOut(sorted[group], into: &counted)
        self.walks = sorted.indices.map { index in
            CountedWalk(
                id: sorted[index].id, startedAt: sorted[index].startedAt, endedAt: sorted[index].endedAt,
                distanceMetres: sorted[index].distanceMetres, countedMetres: counted[index])
        }
    }

    /// Shares out the time of a group of walks that overlap. In each stretch
    /// between two starts or ends, the fastest walk in it counts, and the
    /// earlier of two equally fast walks. A walk without a duration counts
    /// nothing in the time of another walk.
    private static func shareOut(_ group: ArraySlice<RecordedWalk>, into counted: inout [Double]) {
        guard group.count > 1 else { return }
        let times = Set(group.flatMap { [$0.startedAt, $0.endedAt] }).sorted()
        for index in group.indices {
            counted[index] = 0
        }
        for (from, to) in zip(times, times.dropFirst()) {
            var fastest: (index: Int, metresPerSecond: Double)?
            for index in group.indices where group[index].startedAt <= from && to <= group[index].endedAt {
                let walk = group[index]
                let speed = walk.distanceMetres / walk.endedAt.timeIntervalSince(walk.startedAt)
                if speed > fastest?.metresPerSecond ?? -1 {
                    fastest = (index, speed)
                }
            }
            if let fastest {
                counted[fastest.index] += fastest.metresPerSecond * to.timeIntervalSince(from)
            }
        }
    }

    /// The total distance of the dog.
    var totalMetres: Double {
        walks.reduce(0) { $0 + $1.countedMetres }
    }

    /// The average distance of a walk, from the distances of the walks
    /// themselves, or nil without walks.
    var averageWalkMetres: Double? {
        walks.isEmpty ? nil : walks.reduce(0) { $0 + $1.distanceMetres } / Double(walks.count)
    }

    /// The walk with the longest distance of its own.
    var longestWalk: CountedWalk? {
        walks.max { $0.distanceMetres < $1.distanceMetres }
    }

    /// The bars of the page that contains the date.
    func page(
        _ unit: DistanceUnit, containing date: Date, now: Date = .now, calendar: Calendar = WeekCalendar.calendar
    ) -> DistancePage {
        let interval = unit.page(containing: date, calendar: calendar)
        var bars: [DistanceBar] = []
        var start = interval.start
        while start < interval.end, let bar = calendar.dateInterval(of: unit.barComponent, for: start) {
            bars.append(DistanceBar(
                interval: bar,
                walkMetres: walks
                    .filter { bar.start <= $0.startedAt && $0.startedAt < bar.end && $0.countedMetres > 0 }
                    .map(\.countedMetres)))
            start = bar.end
        }
        // The average counts the bars from the first walk on that are over,
        // so that a new dog and a day, week or month that has only begun do
        // not pull it down. While none is over, it counts the current bar
        // once that has a walk.
        let walked = bars.filter { bar in walks.first.map { bar.interval.end > $0.startedAt } ?? false }
        let over = walked.filter { $0.interval.end <= now }
        let counted = !over.isEmpty ? over
            : walked.filter { $0.interval.start <= now && now < $0.interval.end && $0.metres > 0 }
        let average = counted.isEmpty ? nil : counted.reduce(0) { $0 + $1.metres } / Double(counted.count)
        return DistancePage(
            unit: unit, interval: interval, bars: bars, averageMetres: average,
            hasEarlier: walks.first.map { $0.startedAt < interval.start } ?? false,
            hasLater: interval.end <= now)
    }
}

extension DogDistance {
    /// Counts the ended walks of one dog.
    init(_ walks: [Walk]) {
        self.init(walks: walks.map { walk in
            (id: walk.id, startedAt: walk.startedAt, endedAt: walk.endedAt ?? walk.startedAt,
             distanceMetres: walk.distanceMetres)
        })
    }
}

/// What one bar of the distance chart covers.
nonisolated enum DistanceUnit: Hashable, Sendable, CaseIterable {
    /// A day, with a page for each week.
    case day
    /// A week, with a page for 12 weeks.
    case week
    /// A month, with a page for each year.
    case month

    static let weeksOnAPage = 12

    var barComponent: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    /// The page that contains the date. A page of weeks ends with the week
    /// of the date, so that the current page ends with the current week.
    func page(containing date: Date, calendar: Calendar) -> DateInterval {
        switch self {
        case .day:
            return calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 0)
        case .week:
            guard let week = calendar.dateInterval(of: .weekOfYear, for: date),
                  let start = calendar.date(byAdding: .weekOfYear, value: 1 - Self.weeksOnAPage, to: week.start)
            else { return DateInterval(start: date, duration: 0) }
            return DateInterval(start: start, end: week.end)
        case .month:
            return calendar.dateInterval(of: .year, for: date) ?? DateInterval(start: date, duration: 0)
        }
    }

    /// A date on the page before (-1) or after (1) the page of the date.
    func date(_ date: Date, movedBy pages: Int, calendar: Calendar) -> Date {
        let moved = switch self {
        case .day: calendar.date(byAdding: .weekOfYear, value: pages, to: date)
        case .week: calendar.date(byAdding: .weekOfYear, value: pages * Self.weeksOnAPage, to: date)
        case .month: calendar.date(byAdding: .year, value: pages, to: date)
        }
        return moved ?? date
    }
}

/// One bar of the distance chart: a day, a week or a month.
nonisolated struct DistanceBar: Equatable, Sendable, Identifiable {
    let interval: DateInterval
    /// The counted distance of each walk that started in the interval and
    /// counts some distance, the oldest first.
    let walkMetres: [Double]

    var id: Date { interval.start }

    var metres: Double {
        walkMetres.reduce(0, +)
    }
}

/// The bars that the distance chart shows at once: the days of a week, 12
/// weeks or the months of a year.
nonisolated struct DistancePage: Equatable, Sendable {
    let unit: DistanceUnit
    let interval: DateInterval
    let bars: [DistanceBar]
    /// The average distance of the bars from the first walk of the dog on
    /// that are over. While none is over, the distance of the current bar if
    /// it has a walk, and nil otherwise.
    let averageMetres: Double?
    /// Whether the dog has walks before the page.
    let hasEarlier: Bool
    /// Whether the page after this one has begun.
    let hasLater: Bool

    var metres: Double {
        bars.reduce(0) { $0 + $1.metres }
    }

    /// The number of walks that count some distance.
    var walkCount: Int {
        bars.reduce(0) { $0 + $1.walkMetres.count }
    }

    /// The bar that contains the date.
    func bar(containing date: Date) -> DistanceBar? {
        bars.first { $0.interval.start <= date && date < $0.interval.end }
    }
}
