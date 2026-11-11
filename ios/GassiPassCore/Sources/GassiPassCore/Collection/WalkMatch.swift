//
//  WalkMatch.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import Foundation

/// What one walk covers, whichever dogs take part. It depends only on the
/// track and the map release, so the app keeps it on disk
/// (`WalkMatchCache`) and matches each walk only once.
public nonisolated struct WalkMatch: Codable, Equatable, Sendable {
    /// A segment that the walk covers, and the parts that it covers.
    public struct Entry: Equatable, Sendable {
        public let segment: MatchedSegment
        public var covered: [CoveredInterval]

        public init(segment: MatchedSegment, covered: [CoveredInterval]) {
            self.segment = segment
            self.covered = covered
        }
    }

    public var entries: [Segment.ID: Entry] = [:]

    public init(entries: [Segment.ID: Entry] = [:]) {
        self.entries = entries
    }
}

/// The part of a segment that one stretch of track covers, in metres from
/// the start of the segment, and the time of the point at the end of the stretch.
public nonisolated struct CoveredInterval: Equatable, Sendable {
    public let date: Date
    public let interval: ClosedRange<Double>

    public init(date: Date, interval: ClosedRange<Double>) {
        self.date = date
        self.interval = interval
    }
}

nonisolated extension [CoveredInterval] {
    /// The intervals as triples of 64-bit numbers (the time, the start and
    /// the end), for the stored matches and the stored collections. A match
    /// holds thousands of intervals, and one value for all of them keeps a
    /// property list fast to read and to write.
    public var data: Data {
        flatMap { [$0.date.timeIntervalSinceReferenceDate, $0.interval.lowerBound, $0.interval.upperBound] }
            .withUnsafeBytes { Data($0) }
    }

    /// The intervals from their `data`. A triple that is not an interval is
    /// left out.
    public init(data: Data) {
        var values = [Double](repeating: 0, count: data.count / MemoryLayout<Double>.size)
        _ = values.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        self = stride(from: 0, to: values.count - 2, by: 3).compactMap { index in
            guard values[index + 1] <= values[index + 2] else { return nil }
            return CoveredInterval(
                date: Date(timeIntervalSinceReferenceDate: values[index]), interval: values[index + 1]...values[index + 2])
        }
    }
}

nonisolated extension WalkMatch.Entry: Codable {
    private enum CodingKeys: String, CodingKey {
        case segment, covered
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            segment: try container.decode(MatchedSegment.self, forKey: .segment),
            covered: [CoveredInterval](data: try container.decode(Data.self, forKey: .covered)))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(segment, forKey: .segment)
        try container.encode(covered.data, forKey: .covered)
    }
}

/// What the collected share and the completions need to know about a segment.
public nonisolated struct MatchedSegment: Codable, Equatable, Sendable {
    public let fid: Int
    public let area: Int
    public let street: Street.ID?
    /// The length that the map package gives. Completions add it up.
    public let lengthMetres: Double
    /// The length on the local plane of the engine. The covered parts use the
    /// same plane, so the collected share compares like with like.
    public let planeLengthMetres: Double

    /// Whether the covered parts reach the collected share of this segment.
    public func isCollected(by parts: CoveredParts) -> Bool {
        parts.length >= CollectionRules.collectedShare * planeLengthMetres
    }

    /// This segment as collected at the date.
    public func collected(at date: Date) -> CollectedSegment {
        CollectedSegment(
            fid: fid, area: area, street: street, lengthMetres: lengthMetres, collectedAt: date, markedAt: date)
    }

    public init(fid: Int, area: Int, street: Street.ID?, lengthMetres: Double, planeLengthMetres: Double) {
        self.fid = fid
        self.area = area
        self.street = street
        self.lengthMetres = lengthMetres
        self.planeLengthMetres = planeLengthMetres
    }
}

nonisolated extension WalkMatch.Entry {
    /// The time of the mark that this walk alone gives the segment: the time
    /// of its last point on the segment, or nil if the walk covers less than
    /// the collected share of it, for example where it crosses the segment
    /// at a junction.
    public var markedAt: Date? {
        var parts = CoveredParts()
        covered.forEach { parts.add($0.interval) }
        return segment.isCollected(by: parts) ? covered.map(\.date).max() : nil
    }
}

nonisolated extension WalkMatch {
    /// The segments that this walk alone marks, with the time of each mark.
    public var marks: [Segment.ID: Date] {
        entries.compactMapValues(\.markedAt)
    }
}
