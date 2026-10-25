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
enum LocalSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        LocalSchemaV1.models + [WalkedSegment.self, CollectionBuild.self]
    }

    /// A segment that the walks of a dog cover, at least in part, with its
    /// covered parts. A collected segment also has the time when it became
    /// collected, and what the completions need to know about it.
    @Model
    final class WalkedSegment {
        var dogID: UUID = UUID()
        var segmentID: String = ""
        /// The covered parts, as pairs of metres from the start of the
        /// segment (`CoveredParts.data`).
        var coveredParts: Data = Data()
        /// The time of the walk point that collected the segment, or nil if
        /// the dog has not collected it. The values below count only for a
        /// collected segment.
        var collectedAt: Date?
        /// The feature ID of the segment in the map tiles.
        var fid: Int = 0
        /// The BFS number of the area of the segment.
        var area: Int = 0
        /// The street of the segment, or nil if it has no name.
        var streetName: String?
        var lengthMetres: Double = 0

        init(dogID: UUID, segmentID: String) {
            self.dogID = dogID
            self.segmentID = segmentID
        }
    }

    /// What the stored collections were built from. An update that has the
    /// same input matches no walk.
    @Model
    final class CollectionBuild {
        /// The build of the app and the map packages, because a new build or
        /// new map packages change the collections (`CacheFolder`).
        var version: String = ""
        /// The dogs and the ended walks (`CollectionInput.data`).
        var input: Data = Data()
        /// Whether every walk had a match. A walk without a readable track
        /// has none, so the next update matches it again, also with the
        /// same input.
        var matchedEveryWalk: Bool = false

        init() {}
    }
}

/// The steps from each version of the local store to the next.
enum LocalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            LocalSchemaV1.self, LocalSchemaV2.self, LocalSchemaV3.self, LocalSchemaV4.self, LocalSchemaV5.self,
            LocalSchemaV6.self, LocalSchemaV7.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            // The second version only adds the stored collections.
            .lightweight(fromVersion: LocalSchemaV1.self, toVersion: LocalSchemaV2.self),
            // The third version only adds the area steps.
            .lightweight(fromVersion: LocalSchemaV2.self, toVersion: LocalSchemaV3.self),
            // The fourth version only adds the home base and the ring stamps.
            .lightweight(fromVersion: LocalSchemaV3.self, toVersion: LocalSchemaV4.self),
            // The fifth version only adds the marks of the stored collections.
            .lightweight(fromVersion: LocalSchemaV4.self, toVersion: LocalSchemaV5.self),
            // The sixth version only adds the weekly goals.
            .lightweight(fromVersion: LocalSchemaV5.self, toVersion: LocalSchemaV6.self),
            // The seventh version only adds the history of the stored collections.
            .lightweight(fromVersion: LocalSchemaV6.self, toVersion: LocalSchemaV7.self),
        ]
    }
}
