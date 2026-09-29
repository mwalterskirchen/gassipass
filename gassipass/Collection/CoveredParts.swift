//
//  CoveredParts.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation

/// The covered parts of one segment for one dog, as intervals in metres
/// from the start of the segment. The intervals are sorted and do not
/// overlap. Parts from all walks of the dog add up.
nonisolated struct CoveredParts: Equatable, Sendable {
    private(set) var intervals: [ClosedRange<Double>] = []

    /// The total covered length in metres.
    var length: Double {
        intervals.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
    }

    mutating func add(_ interval: ClosedRange<Double>) {
        var merged = interval
        var result: [ClosedRange<Double>] = []
        result.reserveCapacity(intervals.count + 1)
        for existing in intervals {
            if existing.upperBound < merged.lowerBound || existing.lowerBound > merged.upperBound {
                result.append(existing)
            } else {
                merged = min(existing.lowerBound, merged.lowerBound)...max(existing.upperBound, merged.upperBound)
            }
        }
        let index = result.firstIndex { $0.lowerBound > merged.lowerBound } ?? result.endIndex
        result.insert(merged, at: index)
        intervals = result
    }

    mutating func add(_ other: CoveredParts) {
        for interval in other.intervals {
            add(interval)
        }
    }
}
