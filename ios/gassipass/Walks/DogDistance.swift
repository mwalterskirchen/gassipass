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
/// so a walk counts only the share of its time that no earlier walk of the
/// dog covers. The app does not know how far a walk went during the overlap,
/// so the share of the time stands for the share of the distance.
///
/// A walk counts in the day, week or month in which it started.
nonisolated struct DogDistance: Equatable, Sendable {
    /// A walk of the dog, with the distance that it adds to the total.
    struct CountedWalk: Equatable, Sendable, Identifiable {
        let id: UUID
        let startedAt: Date
        let endedAt: Date
        /// The distance of the walk itself.
        let distanceMetres: Double
        /// The distance of the walk without the share of its time that an
        /// earlier walk covers.
        let countedMetres: Double
    }

    /// The walks, the oldest first.
    let walks: [CountedWalk]

    /// Counts the walks of one dog. The walks can come in any order.
    init(walks: [(id: UUID, startedAt: Date, endedAt: Date, distanceMetres: Double)]) {
        let sorted = walks.sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
        var coveredUntil = Date.distantPast
        self.walks = sorted.map { walk in
            let end = max(walk.endedAt, walk.startedAt)
            // The earlier walks all started before this one, so together they
            // cover this walk from its start to the latest end among them.
            let covered = max(min(end, coveredUntil).timeIntervalSince(walk.startedAt), 0)
            let duration = end.timeIntervalSince(walk.startedAt)
            let share = duration > 0 ? 1 - covered / duration : (walk.startedAt < coveredUntil ? 0 : 1)
            coveredUntil = max(coveredUntil, end)
            return CountedWalk(
                id: walk.id, startedAt: walk.startedAt, endedAt: end,
                distanceMetres: walk.distanceMetres, countedMetres: walk.distanceMetres * share)
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
    func page(_ unit: DistanceUnit, containing date: Date, now: Date = .now, calendar: Calendar = .current) -> DistancePage {
        let interval = unit.page(containing: date, calendar: calendar)
        var bars: [DistanceBar] = []
        var start = interval.start
        while start < interval.end, let bar = calendar.dateInterval(of: unit.barComponent, for: start) {
            bars.append(DistanceBar(
                interval: bar,
                walkMetres: walks.filter { bar.start <= $0.startedAt && $0.startedAt < bar.end }.map(\.countedMetres)))
            start = bar.end
        }
        // The average leaves out the bars before the first walk and after
        // now, so that a new dog and the current week do not look lazy.
        let counted = bars.filter { bar in
            guard let first = walks.first else { return false }
            return bar.interval.end > first.startedAt && bar.interval.start <= now
        }
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
    /// The counted distance of each walk that started in the interval, the
    /// oldest first.
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
    /// The average distance of a bar from the first walk of the dog up to
    /// now, or nil if the page has no such bar.
    let averageMetres: Double?
    /// Whether the dog has walks before the page.
    let hasEarlier: Bool
    /// Whether the page after this one has begun.
    let hasLater: Bool

    var metres: Double {
        bars.reduce(0) { $0 + $1.metres }
    }

    var walkCount: Int {
        bars.reduce(0) { $0 + $1.walkMetres.count }
    }

    /// The bar that contains the date.
    func bar(containing date: Date) -> DistanceBar? {
        bars.first { $0.interval.start <= date && date < $0.interval.end }
    }
}
