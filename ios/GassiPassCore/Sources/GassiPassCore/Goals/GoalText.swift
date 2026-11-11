//
//  GoalText.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation

/// The weekly goals in words.
public enum GoalText {
    /// The goal, for example "Walk 5 km" or "Reach 50% of Dietikon".
    ///
    /// - Parameter areaName: The name of the area with the BFS number.
    public static func title(of goal: WeeklyGoal, areaName: (Area.ID) -> String?) -> String {
        switch goal {
        case .newLength(let metres):
            String(localized: "Collect \(length(metres)) of new segments", bundle: .module)
        case .street(let street?):
            String(localized: "Complete \(street.name)", bundle: .module)
        case .street(nil):
            String(localized: "Complete a street", bundle: .module)
        case .newArea:
            String(localized: "Enter a new area", bundle: .module)
        case .refresh(let metres):
            String(localized: "Refresh \(length(metres)) of old marks", bundle: .module)
        case .distance(let metres):
            String(localized: "Walk \(length(metres))", bundle: .module)
        case .areaStep(let step) where step.step == .completed:
            String(localized: "Complete \(areaName(step.area) ?? "")", bundle: .module)
        case .areaStep(let step):
            String(localized: "Reach \(step.step.inkedShare.formatted(.percent)) of \(areaName(step.area) ?? "")", bundle: .module)
        case .ring(let number):
            String(localized: "Complete ring \(number)", bundle: .module)
        }
    }

    /// The name of the week that starts at the date, for example "Week 42".
    public static func weekName(of weekStart: Date) -> String {
        String(localized: "Week \(WeekCalendar.calendar.component(.weekOfYear, from: weekStart))", bundle: .module)
    }

    /// A length of a goal in kilometres, for example "1.5 km".
    public static func length(_ metres: Double) -> String {
        Measurement(value: metres / 1_000, unit: UnitLength.kilometers)
            .formatted(.measurement(
                width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    /// The progress on a goal with a length, for example "3.2 of 5 km".
    public static func progress(_ metres: Double, of target: Double) -> String {
        let done = (metres / 1_000).formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(done) of \(length(target))", bundle: .module)
    }
}
