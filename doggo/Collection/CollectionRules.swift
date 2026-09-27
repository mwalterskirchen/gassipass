//
//  CollectionRules.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation

/// The rules that decide which segments a dog collects, and which area the
/// walker is in during a walk. Only the collection engine applies them.
nonisolated enum CollectionRules {
    /// A stretch of track, the line between two consecutive points, covers
    /// the part of a segment within this distance of it.
    static let coverRadiusMetres = 20.0

    /// A stretch between two points faster than this speed covers nothing,
    /// for example a car or train trip after the walk.
    static let maximumSpeedKilometresPerHour = 12.0

    /// Points with a worse horizontal accuracy than this radius are ignored.
    /// The track then goes straight from the point before to the point after.
    static let worstHorizontalAccuracyMetres = 30.0

    /// A stretch longer than this covers nothing. After a gap in the track,
    /// for example under trees, a long straight line is a guess and can cross
    /// ways that the walker never used. At walking speed, this length is a gap
    /// of about 70 seconds.
    static let longestStretchMetres = 100.0

    /// A segment is collected when the covered parts reach this share of its
    /// length.
    static let collectedShare = 0.9

    /// During a walk, the current area is the area of the segment nearest to
    /// the walker within this distance. Segments are split at the area
    /// boundaries, so the nearest segment lies in the area of the walker.
    static let currentAreaRadiusMetres = 100.0
}
