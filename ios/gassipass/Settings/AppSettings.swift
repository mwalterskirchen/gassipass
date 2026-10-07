//
//  AppSettings.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import Foundation
import Observation

/// The settings of the app. They are stored on this device and do not
/// sync, because they belong to the phone and not to a dog. A change counts
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

    @ObservationIgnored private let defaults: UserDefaults
    private static let vibrationKey = "vibratesForCollectedSegments"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        vibratesForCollectedSegments = defaults.object(forKey: Self.vibrationKey) as? Bool ?? true
    }
}
