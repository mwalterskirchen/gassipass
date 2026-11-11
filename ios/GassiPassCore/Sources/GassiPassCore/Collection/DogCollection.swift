//
//  DogCollection.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import Foundation

/// The segments that one dog has collected, and the covered parts of every
/// segment that its walks touch.
public nonisolated struct DogCollection: Equatable, Sendable {
    public var coveredParts: [Segment.ID: CoveredParts] = [:]
    public var collected: [Segment.ID: CollectedSegment] = [:]

    public var collectedSegments: Set<Segment.ID> {
        Set(collected.keys)
    }

    /// The number of segments that became collected during the time of a
    /// walk. The app does not store what each walk collected. A collected
    /// segment has the time of the walk point that collected it, and the
    /// walks of one dog do not overlap, so that time lies in one walk only.
    ///
    /// Like the collection, the count comes from all walks (ADR 0002). When
    /// an earlier walk is deleted, a segment that it collected can become
    /// collected on a later walk, and the count of the later walk goes up.
    public func collectedSegmentCount(during time: ClosedRange<Date>) -> Int {
        collected.values.count { time.contains($0.collectedAt) }
    }

    /// The feature IDs of the segments that became collected during the time
    /// of a walk, with the same rules as `collectedSegmentCount(during:)`.
    public func collectedFeatures(during time: ClosedRange<Date>) -> Set<Int> {
        Set(collected.values.filter { time.contains($0.collectedAt) }.map(\.fid))
    }

    public init(coveredParts: [Segment.ID: CoveredParts] = [:], collected: [Segment.ID: CollectedSegment] = [:]) {
        self.coveredParts = coveredParts
        self.collected = collected
    }
}

/// A collected segment with what the completions need to know about it.
public nonisolated struct CollectedSegment: Equatable, Sendable {
    /// The feature ID of the segment in the map tiles.
    public let fid: Int
    public let area: Int
    /// The street of the segment, or nil if it has no name.
    public let street: Street.ID?
    public let lengthMetres: Double
    /// The time of the walk point that made the covered parts reach the
    /// collected share.
    public let collectedAt: Date
    /// The time of the mark: the last point on the segment of the latest
    /// walk that alone covered the collected share of it, and never earlier
    /// than `collectedAt`.
    public var markedAt: Date

    public init(fid: Int, area: Int, street: Street.ID?, lengthMetres: Double, collectedAt: Date, markedAt: Date) {
        self.fid = fid
        self.area = area
        self.street = street
        self.lengthMetres = lengthMetres
        self.collectedAt = collectedAt
        self.markedAt = markedAt
    }
}
