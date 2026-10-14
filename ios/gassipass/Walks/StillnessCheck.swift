//
//  StillnessCheck.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation

/// Decides when the app asks whether a walk has ended, because the walker
/// has not moved for a long time.
nonisolated struct StillnessCheck: Sendable {
    /// The time without movement after which the app asks whether the walk
    /// has ended.
    static let timeWithoutMovement: TimeInterval = 60 * 60

    /// How far the walker must go from the last place of movement to count
    /// as moving. This keeps GPS noise from counting as movement. Points with
    /// a worse accuracy than this radius, for example indoor fixes, never
    /// count as movement.
    static let movementRadiusMetres: Double = 50

    private var lastMovement: Date
    private var lastPlace: TrackPoint?

    init(startedAt: Date) {
        lastMovement = startedAt
    }

    /// The time at which the app asks whether the walk has ended.
    var askAt: Date {
        lastMovement + Self.timeWithoutMovement
    }

    /// The walker answers at the date that the walk has not ended yet. An
    /// answer that is older than the last movement changes nothing, for
    /// example when a walk continues after a relaunch.
    mutating func walkContinues(at date: Date) {
        lastMovement = max(lastMovement, date)
    }

    mutating func add(_ point: TrackPoint) {
        guard point.horizontalAccuracy <= Self.movementRadiusMetres else { return }
        guard let lastPlace else {
            lastPlace = point
            return
        }
        if point.distance(to: lastPlace) > Self.movementRadiusMetres {
            self.lastPlace = point
            lastMovement = point.timestamp
        }
    }
}
