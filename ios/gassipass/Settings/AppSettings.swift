//
//  AppSettings.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import Foundation
import Observation

/// The settings of the app. They are stored on this device and do not
/// upload, because they belong to the phone and not to a dog. A change counts
/// at once, also during the current walk.
@Observable
final class AppSettings {
    /// Whether the phone vibrates during a walk when a segment becomes
    /// collected. It starts on.
    var vibratesForCollectedSegments: Bool {
        didSet {
            defaults.set(vibratesForCollectedSegments, forKey: Self.vibrationKey)
        }
    }

    /// Whether the phone notifies on Monday at 08:00 that the dogs have new
    /// weekly goals. It starts on.
    var notifiesAboutNewGoals: Bool {
        didSet {
            defaults.set(notifiesAboutNewGoals, forKey: Self.newGoalsKey)
        }
    }

    /// Whether the phone notifies on Sunday at 17:00 when the week stamp of
    /// a dog needs one more goal. It starts on.
    var notifiesAboutLastGoal: Bool {
        didSet {
            defaults.set(notifiesAboutLastGoal, forKey: Self.lastGoalKey)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let vibrationKey = "vibratesForCollectedSegments"
    private static let newGoalsKey = "notifiesAboutNewGoals"
    private static let lastGoalKey = "notifiesAboutLastGoal"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        vibratesForCollectedSegments = defaults.object(forKey: Self.vibrationKey) as? Bool ?? true
        notifiesAboutNewGoals = defaults.object(forKey: Self.newGoalsKey) as? Bool ?? true
        notifiesAboutLastGoal = defaults.object(forKey: Self.lastGoalKey) as? Bool ?? true
    }
}
