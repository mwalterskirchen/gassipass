//
//  WalkActivityAttributes.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
#if os(iOS)
import ActivityKit
#endif

/// The data of the Live Activity of the walk that is being recorded. The app
/// and the widget extension both use this type.
public nonisolated struct WalkActivityAttributes: Codable, Sendable {
    /// The live figures of the walk. The app updates them while it records.
    public struct ContentState: Codable, Hashable, Sendable {
        /// Whether the app receives GPS points, like the walk screen shows it.
        public enum LocationStatus: Codable, Hashable, Sendable {
            case waiting
            case recording
            case unavailable
            case denied
        }

        /// The live completion of the current area for one dog on the walk.
        public struct DogCompletion: Codable, Hashable, Sendable {
            public let dogName: String
            /// The completion from 0 to 1.
            public let share: Double

            public init(dogName: String, share: Double) {
                self.dogName = dogName
                self.share = share
            }
        }

        public var distanceMetres: Double
        /// The area that the walker is in, or nil before it is known.
        public var areaName: String?
        /// The live completion of the current area for each dog, sorted by name.
        public var completions: [DogCompletion]
        /// The number of segments that became collected on this walk for at
        /// least one dog on the walk.
        public var collectedSegmentCount: Int
        public var locationStatus: LocationStatus

        public init(
            distanceMetres: Double,
            areaName: String? = nil,
            completions: [DogCompletion],
            collectedSegmentCount: Int,
            locationStatus: LocationStatus
        ) {
            self.distanceMetres = distanceMetres
            self.areaName = areaName
            self.completions = completions
            self.collectedSegmentCount = collectedSegmentCount
            self.locationStatus = locationStatus
        }
    }

    /// The names of the dogs as a list, for example "Bello and Luna".
    public let dogNames: String
    public let startedAt: Date

    /// Whether both attributes belong to the same walk.
    public func isSameWalk(as other: WalkActivityAttributes) -> Bool {
        // The system encodes the attributes, so compare the start times
        // with a tolerance.
        abs(startedAt.timeIntervalSince(other.startedAt)) < 1
    }

    public init(dogNames: String, startedAt: Date) {
        self.dogNames = dogNames
        self.startedAt = startedAt
    }
}

// A Mac, where only the tests run, has no Live Activities.
#if os(iOS)
extension WalkActivityAttributes: ActivityAttributes {}
#endif
