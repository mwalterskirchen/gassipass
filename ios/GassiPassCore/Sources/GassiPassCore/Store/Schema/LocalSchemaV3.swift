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
public enum LocalSchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
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
    public final class AreaStep: UploadingRow {
        @Attribute(.unique) public var id: UUID = UUID()
        public var dogID: UUID = UUID()
        /// The BFS number of the area.
        public var area: Int = 0
        /// The step (`StampStep.rawValue`): 0 for the entry stamp, or 25, 50
        /// or 75.
        public var step: Int = 0
        public var reachedAt: Date = Date.now

        public var isWaitingToUpload: Bool = true
        public var changedAt: Date = Date.now
        public var deletedAt: Date?

        public init(id: UUID = UUID(), dogID: UUID, area: Int, step: Int, reachedAt: Date) {
            self.id = id
            self.dogID = dogID
            self.area = area
            self.step = step
            self.reachedAt = reachedAt
        }
    }
}
