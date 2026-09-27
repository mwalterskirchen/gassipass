//
//  CollectionRules.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation

/// The rules that decide which segments a dog collects. Only the collection
/// engine applies them.
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

    /// A segment is collected when the covered parts reach this share of its
    /// length.
    static let collectedShare = 0.9
}
