//
//  WeeklyGoal.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation

/// One of the three weekly goals of a dog for one week. A goal with a
/// length asks for that many metres in the week.
nonisolated enum WeeklyGoal: Hashable, Sendable {
    /// Collect the length of new segments.
    case newLength(metres: Double)
    /// Complete the street, or any street for nil.
    case street(Street.ID?)
    /// Collect the first segment in an area that the dog has not entered.
    case newArea
    /// Refresh the length of marks that are older than two weeks.
    case refresh(metres: Double)
    /// Walk the distance. The app no longer makes this goal, because the
    /// distance earns no stamp, but the sets of earlier weeks keep it.
    case distance(metres: Double)
    /// Reach the step of the stamp of the area.
    case areaStep(AreaStepID)
    /// Complete the ring with the number, around the home base.
    case ring(Int)

    /// The length that the goal asks for, or nil for a goal that a stamp
    /// finishes.
    var targetMetres: Double? {
        switch self {
        case .newLength(let metres), .refresh(let metres), .distance(let metres): metres
        case .street, .newArea, .areaStep, .ring: nil
        }
    }
}

/// A weekly goal with the time at which the dog first finished it, or nil.
nonisolated struct GoalSlot: Hashable, Sendable {
    var goal: WeeklyGoal
    var finishedAt: Date?
}

/// The three weekly goals of one dog for one week (ADR 0007). Every phone
/// of the pack shows the same set, and the server keeps one set for each
/// dog and week.
nonisolated struct WeeklyGoalSet: Hashable, Sendable {
    static let slotCount = 3

    let dog: UUID
    /// The start of the week (`WeekCalendar`).
    let weekStart: Date
    /// The easy, the middle and the hard goal.
    var slots: [GoalSlot]
    /// The index of the slot whose goal a member swapped, or nil. A set has
    /// one swap only.
    var swappedSlot: Int?

    var week: DateInterval {
        WeekCalendar.week(startingAt: weekStart)
    }

    var finishedCount: Int {
        slots.count { $0.finishedAt != nil }
    }

    /// The dog gets a week stamp for a week in which it finished all three
    /// goals.
    var hasWeekStamp: Bool {
        finishedCount == Self.slotCount
    }

    /// The date of the week stamp: the time at which the dog finished the
    /// last of the three goals, or nil without a week stamp.
    var weekStampDate: Date? {
        hasWeekStamp ? slots.compactMap(\.finishedAt).max() : nil
    }
}
