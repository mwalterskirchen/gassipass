//
//  StoredGoalSet.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// A weekly goal in the columns of the server and of the store: a kind, a
/// target for the kinds with a length (metres) or for the step of an area
/// (`StampStep.rawValue`), and an area, a street or a ring where the kind
/// needs one.
nonisolated struct GoalColumns: Equatable, Sendable {
    var kind: String
    var target: Double?
    var area: Int?
    var street: String?
    var ring: Int?

    init(kind: String, target: Double? = nil, area: Int? = nil, street: String? = nil, ring: Int? = nil) {
        self.kind = kind
        self.target = target
        self.area = area
        self.street = street
        self.ring = ring
    }

    init(_ goal: WeeklyGoal) {
        switch goal {
        case .newLength(let metres): self.init(kind: "new_length", target: metres)
        case .street(let street): self.init(kind: "street", area: street?.area, street: street?.name)
        case .newArea: self.init(kind: "new_area")
        case .refresh(let metres): self.init(kind: "refresh", target: metres)
        case .distance(let metres): self.init(kind: "distance", target: metres)
        case .areaStep(let step): self.init(kind: "step", target: Double(step.step.rawValue), area: step.area)
        case .ring(let number): self.init(kind: "step", ring: number)
        }
    }

    /// The goal, or nil for a goal that this build does not know.
    var goal: WeeklyGoal? {
        switch kind {
        case "new_length": target.map { .newLength(metres: $0) }
        case "street":
            if let area, let street { .street(Street.ID(area: area, name: street)) } else { .street(nil) }
        case "new_area": .newArea
        case "refresh": target.map { .refresh(metres: $0) }
        case "distance": target.map { .distance(metres: $0) }
        case "step":
            if let ring {
                .ring(ring)
            } else if let area, let step = target.flatMap({ StampStep(rawValue: Int($0)) }) {
                .areaStep(AreaStepID(area: area, step: step))
            } else {
                nil
            }
        default: nil
        }
    }
}

/// A slot of a set in the columns of the server and of the store.
nonisolated struct GoalSlotColumns: Equatable, Sendable {
    var goal: GoalColumns
    var finishedAt: Date?
}

nonisolated extension WeeklyGoalSet {
    /// The set from the columns, or nil when this build does not know one
    /// of its goals, or the set has no three slots.
    init?(dog: UUID, weekStart: Date, columns: [GoalSlotColumns], swappedSlot: Int?) {
        let slots = columns.compactMap { slot in slot.goal.goal.map { GoalSlot(goal: $0, finishedAt: slot.finishedAt) } }
        guard slots.count == Self.slotCount, columns.count == Self.slotCount else { return nil }
        self.init(dog: dog, weekStart: weekStart, slots: slots, swappedSlot: swappedSlot.map { $0 - 1 })
    }

    var columns: [GoalSlotColumns] {
        slots.map { GoalSlotColumns(goal: GoalColumns($0.goal), finishedAt: $0.finishedAt) }
    }

    /// The swapped slot as the columns keep it, from 1.
    var swappedSlotColumn: Int? {
        swappedSlot.map { $0 + 1 }
    }
}

extension StoredGoalSet {
    /// Stores the set as a new row that uploads.
    convenience init(_ set: WeeklyGoalSet, context: ModelContext) {
        self.init(dogID: set.dog, weekStart: set.weekStart)
        update(to: set)
        context.insert(self)
    }

    /// The set, or nil when this build does not know one of its goals.
    var goalSet: WeeklyGoalSet? {
        WeeklyGoalSet(dog: dogID, weekStart: weekStart, columns: columns, swappedSlot: swappedSlot)
    }

    /// The slots in the columns of the server.
    var columns: [GoalSlotColumns] {
        get {
            [
                GoalSlotColumns(
                    goal: GoalColumns(
                        kind: goal1Kind, target: goal1Target, area: goal1Area, street: goal1Street, ring: goal1Ring),
                    finishedAt: goal1FinishedAt),
                GoalSlotColumns(
                    goal: GoalColumns(
                        kind: goal2Kind, target: goal2Target, area: goal2Area, street: goal2Street, ring: goal2Ring),
                    finishedAt: goal2FinishedAt),
                GoalSlotColumns(
                    goal: GoalColumns(
                        kind: goal3Kind, target: goal3Target, area: goal3Area, street: goal3Street, ring: goal3Ring),
                    finishedAt: goal3FinishedAt),
            ]
        }
        set {
            guard newValue.count == WeeklyGoalSet.slotCount else { return }
            set(\.goal1Kind, to: newValue[0].goal.kind)
            set(\.goal1Target, to: newValue[0].goal.target)
            set(\.goal1Area, to: newValue[0].goal.area)
            set(\.goal1Street, to: newValue[0].goal.street)
            set(\.goal1Ring, to: newValue[0].goal.ring)
            set(\.goal1FinishedAt, to: newValue[0].finishedAt)
            set(\.goal2Kind, to: newValue[1].goal.kind)
            set(\.goal2Target, to: newValue[1].goal.target)
            set(\.goal2Area, to: newValue[1].goal.area)
            set(\.goal2Street, to: newValue[1].goal.street)
            set(\.goal2Ring, to: newValue[1].goal.ring)
            set(\.goal2FinishedAt, to: newValue[1].finishedAt)
            set(\.goal3Kind, to: newValue[2].goal.kind)
            set(\.goal3Target, to: newValue[2].goal.target)
            set(\.goal3Area, to: newValue[2].goal.area)
            set(\.goal3Street, to: newValue[2].goal.street)
            set(\.goal3Ring, to: newValue[2].goal.ring)
            set(\.goal3FinishedAt, to: newValue[2].finishedAt)
        }
    }

    /// Gives the row the goals, the finishes and the swap of the set. It
    /// writes only the values that changed.
    func update(to set: WeeklyGoalSet) {
        columns = set.columns
        self.set(\.swappedSlot, to: set.swappedSlotColumn)
    }
}
