//
//  LocalSchemaV7.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 25.10.2026.
//

import Foundation
import SwiftData

/// The seventh version of the local store: the models of `LocalSchemaV6`,
/// and the history of the stored collections (`CollectionHistory`), so that
/// an update adds a new walk without the other walks (ADR 0002).
///
/// The history is new in `WalkedSegment` and `CollectionBuild`. They have
/// no relationship, so the other models stay shared with `LocalSchemaV6`.
public enum LocalSchemaV7: VersionedSchema {
    public static let versionIdentifier = Schema.Version(7, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            LocalSchemaV4.Pack.self, LocalSchemaV4.Dog.self, LocalSchemaV4.Walk.self, LocalSchemaV4.WalkDog.self,
            LocalSchemaV4.CompletedArea.self, LocalSchemaV4.CompletedStreet.self, LocalSchemaV1.PinnedArea.self,
            WalkedSegment.self, CollectionBuild.self, LocalSchemaV3.AreaStep.self, LocalSchemaV4.CompletedRing.self,
            LocalSchemaV6.StoredGoalSet.self,
        ]
    }

    /// A segment that the walks of a dog cover, at least in part, with its
    /// covered parts and its history (`CoverageHistory.Entry`). A collected
    /// segment also has the time when it became collected and the time of
    /// its mark.
    @Model
    public final class WalkedSegment {
        public var dogID: UUID = UUID()
        public var segmentID: String = ""
        /// The covered parts, as pairs of metres from the start of the
        /// segment (`CoveredParts.data`).
        public var coveredParts: Data = Data()
        /// The time of the walk point that collected the segment, or nil if
        /// the dog has not collected it.
        public var collectedAt: Date?
        /// The time of the mark (`CollectedSegment.markedAt`), or nil if the
        /// dog has not collected the segment.
        public var markedAt: Date?
        /// The feature ID of the segment in the map tiles.
        public var fid: Int = 0
        /// The BFS number of the area of the segment.
        public var area: Int = 0
        /// The street of the segment, or nil if it has no name.
        public var streetName: String?
        public var lengthMetres: Double = 0
        /// The length on the local plane of the engine, for the collected
        /// share (`MatchedSegment.planeLengthMetres`).
        public var planeLengthMetres: Double = 0
        /// The covered intervals that the history keeps
        /// (`CoverageHistory.Entry.covered`, `[CoveredInterval].data`). A
        /// row from before the history has none, and the first update
        /// rebuilds the collections.
        public var keptIntervals: Data = Data()
        /// The latest mark that a walk alone gave the segment, or nil
        /// (`CoverageHistory.Entry.markedAt`).
        public var walkMarkedAt: Date?

        public init(dogID: UUID, segmentID: String) {
            self.dogID = dogID
            self.segmentID = segmentID
        }
    }

    /// The version and the input of the stored collections, and the walks
    /// that their history holds.
    @Model
    public final class CollectionBuild {
        /// The build of the app and the map packages, because a new build or
        /// new map packages change the collections (`CacheFolder`).
        public var version: String = ""
        /// The dogs and the ended walks (`CollectionInput.data`).
        public var input: Data = Data()
        /// Whether every walk had a match. A walk without a readable track
        /// has none, so the next update matches it again, also with the
        /// same input.
        public var matchedEveryWalk: Bool = false
        /// The walks that the history of the stored collections holds
        /// (`CollectionHistory.walks`), or empty for a build from before the
        /// history.
        public var heldWalks: Data = Data()

        public init() {}
    }
}

public typealias WalkedSegment = LocalSchemaV7.WalkedSegment
public typealias CollectionBuild = LocalSchemaV7.CollectionBuild
