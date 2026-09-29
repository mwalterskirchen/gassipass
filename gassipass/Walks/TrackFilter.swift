//
//  TrackFilter.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import Foundation

/// Takes the raw points of a walk one at a time and passes on the points
/// that show where the walker was. The map draws these points, and the
/// distance of the walk is calculated from them.
///
/// It leaves out inaccurate points, for example while the GPS finds its
/// position, and GPS jumps. A GPS jump is a point, or a short run of points,
/// that is farther from the last passed point than the walker can walk, and
/// that comes back within a short time.
nonisolated struct TrackFilter: Sendable {
    /// Points with a worse horizontal accuracy than this radius do not pass.
    static let worstHorizontalAccuracyMetres = 20.0

    /// A point farther from the last passed point than this speed allows is
    /// the start of a jump.
    static let maximumSpeedKilometresPerHour = 15.0

    /// A jump that lasts this long is not a jump but a real movement, for
    /// example a car trip after the walk. Its points then pass.
    static let longestJumpSeconds: TimeInterval = 30

    private var lastPassed: TrackPoint?
    /// The points since the start of a jump that has not come back yet.
    private var jump: [TrackPoint] = []

    init() {}

    /// The points that pass, in the order of recording. A point of a jump
    /// passes later, when the jump turns out to be a real movement.
    mutating func add(_ point: TrackPoint) -> [TrackPoint] {
        // Core Location gives a negative accuracy for a point that is not valid.
        guard (0...Self.worstHorizontalAccuracyMetres).contains(point.horizontalAccuracy) else { return [] }
        guard let lastPassed, !Self.isWalkable(from: lastPassed, to: point) else {
            jump = []
            self.lastPassed = point
            return [point]
        }
        jump.append(point)
        guard point.timestamp.timeIntervalSince(jump[0].timestamp) >= Self.longestJumpSeconds else { return [] }
        let passed = jump
        jump = []
        self.lastPassed = point
        return passed
    }

    /// Whether the walker can go from one point to the other in the time between them.
    static func isWalkable(from: TrackPoint, to: TrackPoint) -> Bool {
        let seconds = to.timestamp.timeIntervalSince(from.timestamp)
        return from.distance(to: to) <= max(seconds, 0) * maximumSpeedKilometresPerHour / 3.6
    }
}

nonisolated extension Track {
    /// The points that show where the walker was, without inaccurate points
    /// and GPS jumps (`TrackFilter`).
    var filteredPoints: [TrackPoint] {
        var filter = TrackFilter()
        return points.flatMap { filter.add($0) }
    }
}
