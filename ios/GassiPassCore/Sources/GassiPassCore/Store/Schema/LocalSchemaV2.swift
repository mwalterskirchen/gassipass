//
//  LocalSchemaV2.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 12.10.2026.
//

import Foundation
import SwiftData

/// The second version of the local store: the models of `LocalSchemaV1`, and
/// the stored collections. The collections are only a cache of the
/// calculation from the walks (ADR 0002). They let the app show the numbers
/// at once at launch. They never upload, because each phone calculates them
/// from its own map packages.
public enum LocalSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        LocalSchemaV1.models + [WalkedSegment.self, CollectionBuild.self]
    }

    /// A segment that the walks of a dog cover, at least in part, with its
    /// covered parts. A collected segment also has the time when it became
    /// collected, and what the completions need to know about it.
    @Model
    public final class WalkedSegment {
        public var dogID: UUID = UUID()
        public var segmentID: String = ""
        /// The covered parts, as pairs of metres from the start of the
        /// segment (`CoveredParts.data`).
        public var coveredParts: Data = Data()
        /// The time of the walk point that collected the segment, or nil if
        /// the dog has not collected it. The values below count only for a
        /// collected segment.
        public var collectedAt: Date?
        /// The feature ID of the segment in the map tiles.
        public var fid: Int = 0
        /// The BFS number of the area of the segment.
        public var area: Int = 0
        /// The street of the segment, or nil if it has no name.
        public var streetName: String?
        public var lengthMetres: Double = 0

        public init(dogID: UUID, segmentID: String) {
            self.dogID = dogID
            self.segmentID = segmentID
        }
    }

    /// What the stored collections were built from. An update that has the
    /// same input matches no walk.
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

        public init() {}
    }
}
