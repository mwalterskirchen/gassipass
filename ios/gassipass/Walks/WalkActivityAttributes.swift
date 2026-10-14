//
//  WalkActivityAttributes.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import ActivityKit
import Foundation

/// The data of the Live Activity of the walk that is being recorded. The app
/// and the widget extension both use this type.
nonisolated struct WalkActivityAttributes: ActivityAttributes, Sendable {
    /// The live figures of the walk. The app updates them while it records.
    struct ContentState: Codable, Hashable, Sendable {
        /// Whether the app receives GPS points, like the walk screen shows it.
        enum LocationStatus: Codable, Hashable, Sendable {
            case waiting
            case recording
            case unavailable
            case denied
        }

        /// The live completion of the current area for one dog on the walk.
        struct DogCompletion: Codable, Hashable, Sendable {
            let dogName: String
            /// The completion from 0 to 1.
            let share: Double
        }

        var distanceMetres: Double
        /// The area that the walker is in, or nil before it is known.
        var areaName: String?
        /// The live completion of the current area for each dog, sorted by name.
        var completions: [DogCompletion]
        /// The number of segments that became collected on this walk for at
        /// least one dog on the walk.
        var collectedSegmentCount: Int
        var locationStatus: LocationStatus
    }

    /// The names of the dogs as a list, for example "Bello and Luna".
    let dogNames: String
    let startedAt: Date

    /// Whether both attributes belong to the same walk.
    func isSameWalk(as other: WalkActivityAttributes) -> Bool {
        // The system encodes the attributes, so compare the start times
        // with a tolerance.
        abs(startedAt.timeIntervalSince(other.startedAt)) < 1
    }
}
