//
//  WalkMonth.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 12.10.2026.
//

import Foundation

/// The walks that started in one month, for a section of the walk list.
struct WalkMonth: Identifiable {
    /// The start of the month.
    let start: Date
    let walks: [Walk]

    var id: Date { start }

    /// The sum of the distances of the walks.
    var distanceMetres: Double {
        walks.reduce(0) { $0 + $1.distanceMetres }
    }

    /// Groups the walks by the month in which they started. The walks keep
    /// their order, so walks with the newest first give the newest month
    /// first.
    static func grouping(_ walks: [Walk], calendar: Calendar = .current) -> [WalkMonth] {
        var months: [WalkMonth] = []
        var start: Date?
        var walksOfMonth: [Walk] = []
        for walk in walks {
            let startOfMonth = calendar.dateInterval(of: .month, for: walk.startedAt)?.start ?? walk.startedAt
            if startOfMonth != start {
                if let start {
                    months.append(WalkMonth(start: start, walks: walksOfMonth))
                }
                start = startOfMonth
                walksOfMonth = []
            }
            walksOfMonth.append(walk)
        }
        if let start {
            months.append(WalkMonth(start: start, walks: walksOfMonth))
        }
        return months
    }
}
