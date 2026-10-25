//
//  MarkedFeatures.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation

/// The collected segments of a map, with the shade of their marks, so that
/// the map shows where the dogs walk most often.
///
/// A mark is one walk over a collected segment in the last four weeks
/// (`CollectionRules.markSeconds`). There are three shades: marked once, a
/// few times and often (`CollectionRules.markShadeMinimums`). A collected
/// segment without a mark has no shade, and the map draws it in the plain
/// collected colour, so it never looks less collected than on the day the
/// dog collected it.
nonisolated struct MarkedFeatures: Equatable, Sendable {
    static let shadeCount = CollectionRules.markShadeMinimums.count

    /// The feature IDs of all the collected segments.
    let all: Set<Int>
    /// The feature IDs of the segments in each shade, from marked once to
    /// marked often.
    let shades: [Set<Int>]

    /// The collected segments without their marks, for a map that does not
    /// show the marks.
    init(collected features: Set<Int> = []) {
        all = features
        shades = Array(repeating: [], count: Self.shadeCount)
    }

    /// The segments that every dog has collected, each in the shade of the
    /// dog that marked it least. Without dogs there are none.
    ///
    /// - Parameter dogs: The collection of each dog, with the times of the
    ///   marks of its walks by segment.
    init(dogs: [(collection: DogCollection, marks: [Segment.ID: [Date]])], at now: Date) {
        var all: Set<Int> = []
        var shades = Array(repeating: Set<Int>(), count: Self.shadeCount)
        if let first = dogs.first {
            for (id, segment) in first.collection.collected {
                let counts = dogs.compactMap { dog in
                    dog.collection.collected[id].map { Self.markCount(of: $0, marks: dog.marks[id] ?? [], at: now) }
                }
                guard counts.count == dogs.count, let count = counts.min() else { continue }
                all.insert(segment.fid)
                if let shade = Self.shade(ofMarkCount: count) {
                    shades[shade].insert(segment.fid)
                }
            }
        }
        self.all = all
        self.shades = shades
    }

    /// The number of marks of the collected segment in the four weeks before
    /// the date. A segment that the dog collected in that time has at least
    /// one, also when no walk alone covered it.
    static func markCount(of segment: CollectedSegment, marks: [Date], at now: Date) -> Int {
        let start = now - CollectionRules.markSeconds
        let count = marks.count { $0 >= start }
        return count == 0 && segment.collectedAt >= start ? 1 : count
    }

    /// The shade of a number of marks, or nil without a mark.
    static func shade(ofMarkCount count: Int) -> Int? {
        CollectionRules.markShadeMinimums.lastIndex { count >= $0 }
    }
}
