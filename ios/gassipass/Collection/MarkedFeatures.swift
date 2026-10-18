//
//  MarkedFeatures.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation

/// The collected segments of a map by the age of their marks, so that the
/// map draws a mark paler as it fades.
///
/// There are five age bands. Each of the first four is a week of the four
/// weeks in which a mark fades (`CollectionRules.markFadeSeconds`), and the
/// fifth holds the faded marks.
nonisolated struct MarkedFeatures: Equatable, Sendable {
    static let bandCount = 5
    /// The last band, which holds the faded marks.
    static let fadedBand = bandCount - 1

    /// The feature IDs of the segments in each age band, from the freshest.
    let bands: [Set<Int>]

    /// The feature IDs of all the segments.
    var all: Set<Int> {
        bands.reduce([]) { $0.union($1) }
    }

    /// The segments, all with fresh marks, for a map that does not show
    /// the marks.
    init(fresh features: Set<Int> = []) {
        bands = [features] + Array(repeating: [], count: Self.bandCount - 1)
    }

    /// The segments that every one of the collections holds, each in the
    /// band of its oldest mark. Without collections there are none.
    init(collections: [DogCollection], at now: Date) {
        var bands = Array(repeating: Set<Int>(), count: Self.bandCount)
        if let first = collections.first {
            for (id, segment) in first.collected {
                let marks = collections.compactMap { $0.collected[id]?.markedAt }
                guard marks.count == collections.count, let oldest = marks.min() else { continue }
                bands[Self.band(markedAt: oldest, at: now)].insert(segment.fid)
            }
        }
        self.bands = bands
    }

    /// The age band of a mark: the number of whole weeks since the mark,
    /// up to the band of the faded marks.
    static func band(markedAt: Date, at now: Date) -> Int {
        let week = CollectionRules.markFadeSeconds / Double(fadedBand)
        let weeks = Int((now.timeIntervalSince(markedAt) / week).rounded(.down))
        return min(max(weeks, 0), fadedBand)
    }
}

nonisolated extension CollectedSegment {
    /// Whether the mark has not faded yet at the date.
    func isMarked(at now: Date) -> Bool {
        now.timeIntervalSince(markedAt) < CollectionRules.markFadeSeconds
    }
}
