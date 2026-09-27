//
//  Completion.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation

/// The collected length of an area as a share of its total length, for one
/// dog, and the number of collected segments.
nonisolated struct Completion: Equatable, Sendable {
    let collectedLengthMetres: Double
    let lengthMetres: Double
    let collectedSegmentCount: Int
    let segmentCount: Int

    /// The completion from 0 to 1.
    var share: Double {
        lengthMetres > 0 ? collectedLengthMetres / lengthMetres : 0
    }
}

nonisolated extension DogCollection {
    /// The completion of an area for this dog.
    func completion(of area: Area) -> Completion {
        let segments = collected.values.filter { $0.area == area.id }
        return Completion(
            collectedLengthMetres: segments.reduce(0) { $0 + $1.lengthMetres },
            lengthMetres: area.lengthMetres,
            collectedSegmentCount: segments.count,
            segmentCount: area.segmentCount)
    }
}

/// A permanent record that a dog has completed an area: its completion
/// reached 100% on this date. A map release that later lowers the completion
/// does not remove it.
nonisolated struct CompletedRecord<Dog: Hashable & Sendable>: Hashable, Sendable {
    let dog: Dog
    /// The BFS number of the area.
    let area: Int
    let date: Date
}

nonisolated extension CollectionEngine {
    /// The existing completed records, followed by a new record for each dog
    /// and area that has none yet and whose completion is 100%. The engine
    /// never removes a record.
    ///
    /// The completion of an area reaches 100% when its last segment is
    /// collected, so the date of a new record is the latest date on which a
    /// segment of the area was collected.
    static func completedRecords<Dog>(
        collections: [Dog: DogCollection], areas: [Area], existing: [CompletedRecord<Dog>]
    ) -> [CompletedRecord<Dog>] {
        let areasByID = Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recorded = Set(existing.map { DogArea(dog: $0.dog, area: $0.area) })
        var new: [CompletedRecord<Dog>] = []
        for (dog, collection) in collections {
            let segmentsByArea = Dictionary(grouping: collection.collected.values, by: \.area)
            for (areaID, segments) in segmentsByArea {
                guard let area = areasByID[areaID], segments.count == area.segmentCount,
                      !recorded.contains(DogArea(dog: dog, area: areaID)),
                      let date = segments.map(\.collectedAt).max()
                else { continue }
                new.append(CompletedRecord(dog: dog, area: areaID, date: date))
            }
        }
        return existing + new.sorted { $0.date < $1.date }
    }

    /// The date on which the dog completed the area, or nil if it has not.
    /// With two devices there can be two records for the same dog and area,
    /// and the earliest date counts.
    static func completedDate<Dog>(of area: Int, for dog: Dog, in records: [CompletedRecord<Dog>]) -> Date? {
        records.filter { $0.dog == dog && $0.area == area }.map(\.date).min()
    }

    private struct DogArea<Dog: Hashable>: Hashable {
        let dog: Dog
        let area: Int
    }
}
