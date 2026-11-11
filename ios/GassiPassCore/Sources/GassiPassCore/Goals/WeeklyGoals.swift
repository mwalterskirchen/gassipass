//
//  WeeklyGoals.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation

/// The progress of a dog on one weekly goal.
public nonisolated struct GoalProgress: Equatable, Sendable {
    /// The length so far, or nil for a goal that a stamp finishes.
    public let amountMetres: Double?
    /// The time at which the dog finished the goal, or nil.
    public let finishedAt: Date?

    public init(amountMetres: Double?, finishedAt: Date?) {
        self.amountMetres = amountMetres
        self.finishedAt = finishedAt
    }
}

/// The rules of the weekly goals: their progress, the goals that a dog
/// gets, the swap and the week stamp. It has no user interface, storage or
/// networking.
public nonisolated enum WeeklyGoals {
    /// A refresh goal counts a mark that is at least this old, two weeks.
    public static let oldMarkSeconds: TimeInterval = 14 * 86_400

    /// The progress of the dog on the goal with what it did in the week.
    public static func progress(of goal: WeeklyGoal, in events: GoalEvents) -> GoalProgress {
        let records = events.records
        switch goal {
        case .newLength(let metres):
            return progress(of: events.newSegments, target: metres)
        case .refresh(let metres):
            return progress(of: events.refreshed, target: metres)
        case .distance(let metres):
            return progress(of: events.walked, target: metres)
        case .street(let street):
            return stamped(records.streets.filter { street == nil || $0.goal == street })
        case .newArea:
            return stamped(records.steps.filter { $0.goal.step == .entry })
        case .areaStep(let step):
            return stamped(records.steps.filter { $0.goal.area == step.area && $0.goal.step >= step.step })
        case .ring(let number):
            return stamped(records.rings.filter { $0.goal.number >= number })
        }
    }

    /// The sum of the amounts, and the time of the amount that lifted the
    /// sum to the target.
    private static func progress(of amounts: [GoalAmount], target: Double) -> GoalProgress {
        var sum = 0.0
        var finishedAt: Date?
        for amount in amounts.sorted(by: { $0.date < $1.date }) {
            sum += amount.metres
            if finishedAt == nil, sum >= target - lengthTolerance {
                finishedAt = amount.date
            }
        }
        return GoalProgress(amountMetres: sum, finishedAt: finishedAt)
    }

    /// The date of the earliest of the stamps.
    private static func stamped<Goal>(_ records: [CompletedRecord<UUID, Goal>]) -> GoalProgress {
        GoalProgress(amountMetres: nil, finishedAt: records.map(\.date).min())
    }

    /// A sum of lengths that is this close to the target reaches it.
    private static let lengthTolerance = 0.5
}
