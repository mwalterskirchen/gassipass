//
//  GoalText.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation

/// The weekly goals in words.
enum GoalText {
    /// The goal, for example "Walk 5 km" or "Reach 50% of Dietikon".
    ///
    /// - Parameter areaName: The name of the area with the BFS number.
    static func title(of goal: WeeklyGoal, areaName: (Area.ID) -> String?) -> String {
        switch goal {
        case .newLength(let metres):
            String(localized: "Collect \(length(metres)) of new segments")
        case .street(let street?):
            String(localized: "Complete \(street.name)")
        case .street(nil):
            String(localized: "Complete a street")
        case .newArea:
            String(localized: "Enter a new area")
        case .refresh(let metres):
            String(localized: "Refresh \(length(metres)) of old marks")
        case .distance(let metres):
            String(localized: "Walk \(length(metres))")
        case .areaStep(let step) where step.step == .completed:
            String(localized: "Complete \(areaName(step.area) ?? "")")
        case .areaStep(let step):
            String(localized: "Reach \(step.step.inkedShare.formatted(.percent)) of \(areaName(step.area) ?? "")")
        case .ring(let number):
            String(localized: "Complete ring \(number)")
        }
    }

    /// The name of the week that starts at the date, for example "Week 42".
    static func weekName(of weekStart: Date) -> String {
        String(localized: "Week \(WeekCalendar.calendar.component(.weekOfYear, from: weekStart))")
    }

    /// A length of a goal in kilometres, for example "1.5 km".
    static func length(_ metres: Double) -> String {
        Measurement(value: metres / 1_000, unit: UnitLength.kilometers)
            .formatted(.measurement(
                width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    /// The progress on a goal with a length, for example "3.2 of 5 km".
    static func progress(_ metres: Double, of target: Double) -> String {
        let done = (metres / 1_000).formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(done) of \(length(target))")
    }
}
