//
//  LocalSchemaV6.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// The sixth version of the local store: the models of `LocalSchemaV5`, and
/// the weekly goals.
public enum LocalSchemaV6: VersionedSchema {
    public static let versionIdentifier = Schema.Version(6, 0, 0)

    public static var models: [any PersistentModel.Type] {
        LocalSchemaV5.models + [StoredGoalSet.self]
    }

    /// The three weekly goals of one dog for one week (ADR 0007), with the
    /// time at which the dog first finished each one. The server keeps one
    /// set for each dog and week, and of two sets for the same dog and week
    /// the one of the server wins (`PackDownload`).
    ///
    /// Each slot keeps its goal in the columns of the server
    /// (`GoalColumns`). It keeps the ID of its dog and no relationship, like
    /// `AreaStep`.
    @Model
    public final class StoredGoalSet: UploadingRow {
        @Attribute(.unique) public var id: UUID = UUID()
        public var dogID: UUID = UUID()
        /// The start of the week (`WeekCalendar`).
        public var weekStart: Date = Date.now
        public var goal1Kind: String = ""
        public var goal1Target: Double?
        public var goal1Area: Int?
        public var goal1Street: String?
        public var goal1Ring: Int?
        public var goal1FinishedAt: Date?
        public var goal2Kind: String = ""
        public var goal2Target: Double?
        public var goal2Area: Int?
        public var goal2Street: String?
        public var goal2Ring: Int?
        public var goal2FinishedAt: Date?
        public var goal3Kind: String = ""
        public var goal3Target: Double?
        public var goal3Area: Int?
        public var goal3Street: String?
        public var goal3Ring: Int?
        public var goal3FinishedAt: Date?
        /// The slot whose goal a member swapped, from 1, or nil.
        public var swappedSlot: Int?

        public var isWaitingToUpload: Bool = true
        public var changedAt: Date = Date.now
        public var deletedAt: Date?

        public init(id: UUID = UUID(), dogID: UUID, weekStart: Date) {
            self.id = id
            self.dogID = dogID
            self.weekStart = weekStart
        }
    }
}
