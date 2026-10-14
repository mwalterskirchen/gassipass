//
//  DogTotals.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import Foundation

/// The totals of one dog for the dashboard on the home screen.
///
/// The collected length comes from the collection, so it can drop when a
/// walk is deleted or a new map release arrives. The completed counts come
/// from the permanent records, so they never drop.
nonisolated struct DogTotals: Equatable, Sendable {
    /// The total length of all collected segments of the dog.
    let collectedLengthMetres: Double
    let completedAreaCount: Int
    let completedStreetCount: Int
}

nonisolated extension DogTotals {
    /// The totals of the dog. With two devices there can be two records for
    /// the same dog and goal, and they count once. Records of other dogs do
    /// not count.
    init<Dog>(
        collection: DogCollection, dog: Dog,
        areaRecords: [CompletedRecord<Dog, Area.ID>], streetRecords: [CompletedRecord<Dog, Street.ID>]
    ) {
        self.init(
            collectedLengthMetres: collection.collected.values.reduce(0) { $0 + $1.lengthMetres },
            completedAreaCount: Set(areaRecords.filter { $0.dog == dog }.map(\.goal)).count,
            completedStreetCount: Set(streetRecords.filter { $0.dog == dog }.map(\.goal)).count)
    }
}
