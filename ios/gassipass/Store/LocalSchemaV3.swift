//
//  LocalSchemaV3.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import Foundation
import SwiftData

/// The third version of the local store: the models of `LocalSchemaV2`, and
/// the steps of the area stamps.
enum LocalSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        LocalSchemaV2.models + [AreaStep.self]
    }

    /// The permanent record that a dog has reached a step of the stamp of an
    /// area: the entry stamp, or 25%, 50% or 75% completion. The full stamp
    /// is a `CompletedArea`. It follows the rules of `CompletedArea`: with
    /// two phones there can be two records for the same dog, area and step,
    /// and the earliest date counts.
    ///
    /// It keeps the ID of its dog and no relationship. A relationship to
    /// `Dog`, which the earlier versions share, would change their
    /// checksums too, and the migration plan refuses two versions with the
    /// same checksum.
    @Model
    final class AreaStep: UploadingRow {
        @Attribute(.unique) var id: UUID = UUID()
        var dogID: UUID = UUID()
        /// The BFS number of the area.
        var area: Int = 0
        /// The step (`StampStep.rawValue`): 0 for the entry stamp, or 25, 50
        /// or 75.
        var step: Int = 0
        var reachedAt: Date = Date.now

        var isWaitingToUpload: Bool = true
        var changedAt: Date = Date.now
        var deletedAt: Date?

        init(id: UUID = UUID(), dogID: UUID, area: Int, step: Int, reachedAt: Date) {
            self.id = id
            self.dogID = dogID
            self.area = area
            self.step = step
            self.reachedAt = reachedAt
        }
    }
}

typealias AreaStep = LocalSchemaV3.AreaStep
