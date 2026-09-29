//
//  WalkDistance.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import Foundation

/// The distance of a walk, from its raw GPS points.
///
/// The distance uses only the points that pass the track filter. Even these
/// points jump a little around the true place, so the line through them is
/// longer than the way that the walker walked. The distance leaves out
/// these small jumps: it counts a step only when the walker has gone
/// farther from the last counted point than the GPS error.
nonisolated struct WalkDistance: Sendable {
    /// The version of these rules. A walk whose distance comes from an older
    /// version gets its distance again from its track.
    static let version = 1

    /// The shortest step that counts. A step must also be longer than the
    /// accuracy of its point.
    static let shortestStepMetres = 10.0

    /// The distance so far, in metres.
    private(set) var metres: Double = 0
    private var filter = TrackFilter()
    private var lastCounted: TrackPoint?

    init() {}

    init(_ track: Track) {
        track.points.forEach { add($0) }
    }

    mutating func add(_ point: TrackPoint) {
        for passed in filter.add(point) {
            count(passed)
        }
    }

    private mutating func count(_ point: TrackPoint) {
        guard let lastCounted else {
            self.lastCounted = point
            return
        }
        let step = lastCounted.distance(to: point)
        guard step >= max(Self.shortestStepMetres, point.horizontalAccuracy) else { return }
        // A step faster than walking passes the filter only as a real
        // movement, for example a car trip, which is not part of the walk.
        if TrackFilter.isWalkable(from: lastCounted, to: point) {
            metres += step
        }
        self.lastCounted = point
    }
}
