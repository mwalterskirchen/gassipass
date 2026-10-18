//
//  ServerGoalSet.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// The weekly goals of a dog for a week, on the server (ADR 0007). The
/// server keeps one set for each dog and week, the earliest finish of each
/// goal, and one swap. The week is the day of its Monday in Zurich.
nonisolated struct ServerGoalSet: ServerRow, Equatable {
    static let table = ServerTable.weeklyGoals

    var id: UUID
    var packID: UUID
    var dogID: UUID
    var weekStart: Date
    var slots: [GoalSlotColumns]
    /// The slot whose goal a member swapped, from 1, or nil.
    var swappedSlot: Int?
    var deletedAt: Date?

    init(
        id: UUID, packID: UUID, dogID: UUID, weekStart: Date, slots: [GoalSlotColumns], swappedSlot: Int?,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.packID = packID
        self.dogID = dogID
        self.weekStart = weekStart
        self.slots = slots
        self.swappedSlot = swappedSlot
        self.deletedAt = deletedAt
    }

    init(id: UUID, packID: UUID, set: WeeklyGoalSet, deletedAt: Date? = nil) {
        self.init(
            id: id, packID: packID, dogID: set.dog, weekStart: set.weekStart, slots: set.columns,
            swappedSlot: set.swappedSlotColumn, deletedAt: deletedAt)
    }

    /// The set of the row, or nil when this build does not know one of its
    /// goals. Setting it keeps the ID, the pack and the deletion.
    var set: WeeklyGoalSet? {
        get { WeeklyGoalSet(dog: dogID, weekStart: weekStart, columns: slots, swappedSlot: swappedSlot) }
        set {
            guard let newValue else { return }
            self = ServerGoalSet(id: id, packID: packID, set: newValue, deletedAt: deletedAt)
        }
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init(_ stringValue: String) {
            self.stringValue = stringValue
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }

        /// The column of a slot, from 0, for example "goal1_kind".
        static func goal(_ slot: Int, _ column: String) -> Key {
            Key("goal\(slot + 1)_\(column)")
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        id = try container.decode(UUID.self, forKey: Key("id"))
        packID = try container.decode(UUID.self, forKey: Key("pack_id"))
        dogID = try container.decode(UUID.self, forKey: Key("dog_id"))
        let day = try container.decode(String.self, forKey: Key("week_start"))
        guard let weekStart = WeekCalendar.date(ofDayText: day) else {
            throw DecodingError.dataCorruptedError(
                forKey: Key("week_start"), in: container, debugDescription: "The week is no day: \(day)")
        }
        self.weekStart = weekStart
        slots = try (0..<WeeklyGoalSet.slotCount).map { slot in
            GoalSlotColumns(
                goal: GoalColumns(
                    kind: try container.decode(String.self, forKey: .goal(slot, "kind")),
                    target: try container.decodeIfPresent(Double.self, forKey: .goal(slot, "target")),
                    area: try container.decodeIfPresent(Int.self, forKey: .goal(slot, "area")),
                    street: try container.decodeIfPresent(String.self, forKey: .goal(slot, "street")),
                    ring: try container.decodeIfPresent(Int.self, forKey: .goal(slot, "ring"))),
                finishedAt: try container.decodeIfPresent(Date.self, forKey: .goal(slot, "finished_at")))
        }
        swappedSlot = try container.decodeIfPresent(Int.self, forKey: Key("swapped_slot"))
        deletedAt = try container.decodeIfPresent(Date.self, forKey: Key("deleted_at"))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(id, forKey: Key("id"))
        try container.encode(packID, forKey: Key("pack_id"))
        try container.encode(dogID, forKey: Key("dog_id"))
        try container.encode(WeekCalendar.dayText(of: weekStart), forKey: Key("week_start"))
        for (slot, columns) in slots.enumerated() {
            try container.encode(columns.goal.kind, forKey: .goal(slot, "kind"))
            try container.encode(columns.goal.target, forKey: .goal(slot, "target"))
            try container.encode(columns.goal.area, forKey: .goal(slot, "area"))
            try container.encode(columns.goal.street, forKey: .goal(slot, "street"))
            try container.encode(columns.goal.ring, forKey: .goal(slot, "ring"))
            try container.encode(columns.finishedAt, forKey: .goal(slot, "finished_at"))
        }
        try container.encode(swappedSlot, forKey: Key("swapped_slot"))
        try container.encode(deletedAt, forKey: Key("deleted_at"))
    }
}

/// A set of weekly goals finds its dog by its ID, like an area step. The
/// server keeps one set for each dog and week, so a refused set takes the
/// set of the server, and a downloaded set removes a set of this phone for
/// the same dog and week. Its progress comes from the walks, so nothing is
/// lost but a swap.
extension ServerGoalSet: SyncedRow {
    static var waitingRows: FetchDescriptor<StoredGoalSet> {
        FetchDescriptor(predicate: #Predicate<StoredGoalSet> { $0.isWaitingToUpload })
    }

    static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<StoredGoalSet> {
        FetchDescriptor(predicate: #Predicate<StoredGoalSet> {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        })
    }

    static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<StoredGoalSet> {
        FetchDescriptor(predicate: #Predicate<StoredGoalSet> { ids.contains($0.id) })
    }

    static func targets(of local: StoredGoalSet) -> [SyncedTarget]? {
        [.dog(local.dogID)]
    }

    var targets: [SyncedTarget] {
        [.dog(dogID)]
    }

    static var hasUniqueKey: Bool {
        true
    }

    func hasSameKey(as local: StoredGoalSet) -> Bool {
        local.isSet(of: dogID, weekStart: weekStart)
    }

    init(_ local: StoredGoalSet, packID: UUID, filePath: String?) {
        self.init(
            id: local.id, packID: packID, dogID: local.dogID, weekStart: local.weekStart, slots: local.columns,
            swappedSlot: local.swappedSlot, deletedAt: local.deletedAt)
    }

    func store(in local: StoredGoalSet?, targets: StoreTargets) -> StoredGoalSet {
        let goalSet = local ?? StoredGoalSet(id: id, dogID: dogID, weekStart: weekStart)
        goalSet.set(\.dogID, to: dogID)
        goalSet.set(\.weekStart, to: weekStart)
        goalSet.columns = slots
        goalSet.set(\.swappedSlot, to: swappedSlot)
        return goalSet
    }
}
