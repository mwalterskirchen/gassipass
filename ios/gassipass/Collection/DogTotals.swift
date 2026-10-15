//
//  DogTotals.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import Foundation

/// The completed numbers of one dog for the dashboard on the home screen.
///
/// They come from the permanent records, so they never drop.
nonisolated struct DogTotals: Equatable, Sendable {
    let completedAreaCount: Int
    let completedStreetCount: Int
}

nonisolated extension DogTotals {
    /// The totals of the dog. With two devices there can be two records for
    /// the same dog and goal, and they count once. Records of other dogs do
    /// not count.
    init<Dog>(
        dog: Dog, areaRecords: [CompletedRecord<Dog, Area.ID>], streetRecords: [CompletedRecord<Dog, Street.ID>]
    ) {
        self.init(
            completedAreaCount: Set(areaRecords.filter { $0.dog == dog }.map(\.goal)).count,
            completedStreetCount: Set(streetRecords.filter { $0.dog == dog }.map(\.goal)).count)
    }
}
