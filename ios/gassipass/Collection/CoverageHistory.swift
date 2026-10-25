//
//  CoverageHistory.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 25.10.2026.
//

import Foundation

/// What the walks of one dog covered, kept so that a new walk adds to the
/// collection of the dog without the other walks (ADR 0002).
///
/// The date at which a segment becomes collected depends only on the covered
/// intervals of that segment, taken in the order of time. So for each
/// segment the history keeps only the intervals that added to the covered
/// parts in that order. An interval that it drops lay within the parts of
/// earlier intervals, and it stays within them whatever walks come later, so
/// it changes neither the date nor the parts. A walk that is added later,
/// also one that is older than other walks, gives the same collection as
/// a rebuild from all walks. A removed walk needs that rebuild, because its
/// intervals can be the reason why the history dropped others.
nonisolated struct CoverageHistory: Equatable, Sendable {
    /// One segment that the walks of the dog cover.
    struct Entry: Equatable, Sendable {
        let segment: MatchedSegment
        /// The intervals that added to the covered parts, in the order of time.
        private(set) var covered: [CoveredInterval] = []
        /// The covered parts of all walks.
        private(set) var parts = CoveredParts()
        /// The date of the interval that made the parts reach the collected
        /// share, or nil if they do not reach it.
        private(set) var collectedAt: Date?
        /// The latest mark that a walk alone gave the segment, or nil if no
        /// walk alone covered the collected share.
        private(set) var markedAt: Date?

        init(segment: MatchedSegment) {
            self.segment = segment
        }

        /// The entry as a store gave it, from its `covered` and `markedAt`.
        init(segment: MatchedSegment, covered: [CoveredInterval], markedAt: Date?) {
            self.segment = segment
            self.markedAt = markedAt
            add(covered)
        }

        /// Adds the intervals of one walk and its mark.
        mutating func add(_ entry: WalkMatch.Entry) {
            if let mark = entry.markedAt {
                markedAt = max(markedAt ?? mark, mark)
            }
            add(entry.covered)
        }

        private mutating func add(_ intervals: [CoveredInterval]) {
            var kept: [CoveredInterval] = []
            var parts = CoveredParts()
            var collectedAt: Date?
            for interval in (covered + intervals).sorted(by: { $0.date < $1.date })
            where !parts.contains(interval.interval) {
                kept.append(interval)
                parts.add(interval.interval)
                if collectedAt == nil, segment.isCollected(by: parts) {
                    collectedAt = interval.date
                }
            }
            covered = kept
            self.parts = parts
            self.collectedAt = collectedAt
        }
    }

    private(set) var entries: [Segment.ID: Entry] = [:]

    init() {}

    init(entries: [Segment.ID: Entry]) {
        self.entries = entries
    }

    /// Adds what one walk of the dog covered.
    mutating func add(_ match: WalkMatch) {
        for (id, entry) in match.entries {
            entries[id, default: Entry(segment: entry.segment)].add(entry)
        }
    }

    /// The collection of the dog. A collected segment gets the latest of its
    /// marks, and at least its `collectedAt`.
    var collection: DogCollection {
        var collection = DogCollection()
        for (id, entry) in entries {
            collection.coveredParts[id] = entry.parts
            if let collectedAt = entry.collectedAt {
                var collected = entry.segment.collected(at: collectedAt)
                collected.markedAt = max(collectedAt, entry.markedAt ?? collectedAt)
                collection.collected[id] = collected
            }
        }
        return collection
    }
}
