//
//  LocalSchemaV5.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// The fifth version of the local store: the models of `LocalSchemaV4`, and
/// the marks of the stored collections.
///
/// The mark is a new attribute of `WalkedSegment`. The earlier versions
/// share their `WalkedSegment`, so this version has its own. It has no
/// relationship, so the other models stay shared with `LocalSchemaV4`.
enum LocalSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            LocalSchemaV4.Pack.self, LocalSchemaV4.Dog.self, LocalSchemaV4.Walk.self, LocalSchemaV4.WalkDog.self,
            LocalSchemaV4.CompletedArea.self, LocalSchemaV4.CompletedStreet.self, LocalSchemaV1.PinnedArea.self,
            WalkedSegment.self, LocalSchemaV2.CollectionBuild.self, LocalSchemaV3.AreaStep.self,
            LocalSchemaV4.CompletedRing.self,
        ]
    }

    /// A segment that the walks of a dog cover, at least in part, with its
    /// covered parts. A collected segment also has the time when it became
    /// collected, the time of its mark, and what the completions need to
    /// know about it.
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
        /// The time of the mark (`CollectedSegment.markedAt`), or nil for a
        /// row from before the marks. Such a row shows its `collectedAt` as
        /// the mark only until the first update after the upgrade, which
        /// rebuilds every collection because the build of the app is new.
        var markedAt: Date?
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
}

typealias WalkedSegment = LocalSchemaV5.WalkedSegment
