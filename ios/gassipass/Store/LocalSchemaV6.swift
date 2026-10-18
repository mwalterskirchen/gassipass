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
enum LocalSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
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
    final class StoredGoalSet: UploadingRow {
        @Attribute(.unique) var id: UUID = UUID()
        var dogID: UUID = UUID()
        /// The start of the week (`WeekCalendar`).
        var weekStart: Date = Date.now
        var goal1Kind: String = ""
        var goal1Target: Double?
        var goal1Area: Int?
        var goal1Street: String?
        var goal1Ring: Int?
        var goal1FinishedAt: Date?
        var goal2Kind: String = ""
        var goal2Target: Double?
        var goal2Area: Int?
        var goal2Street: String?
        var goal2Ring: Int?
        var goal2FinishedAt: Date?
        var goal3Kind: String = ""
        var goal3Target: Double?
        var goal3Area: Int?
        var goal3Street: String?
        var goal3Ring: Int?
        var goal3FinishedAt: Date?
        /// The slot whose goal a member swapped, from 1, or nil.
        var swappedSlot: Int?

        var isWaitingToUpload: Bool = true
        var changedAt: Date = Date.now
        var deletedAt: Date?

        init(id: UUID = UUID(), dogID: UUID, weekStart: Date) {
            self.id = id
            self.dogID = dogID
            self.weekStart = weekStart
        }
    }
}

typealias StoredGoalSet = LocalSchemaV6.StoredGoalSet
