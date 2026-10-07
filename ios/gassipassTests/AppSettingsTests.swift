//
//  AppSettingsTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import Foundation
import Testing
@testable import gassipass

/// Each test uses its own user defaults, so that it does not touch the
/// settings of the app.
@MainActor
struct AppSettingsTests {
    let defaults = UserDefaults(suiteName: "AppSettingsTests-\(UUID().uuidString)")!

    @Test func theVibrationStartsOn() {
        #expect(AppSettings(defaults: defaults).vibratesForCollectedSegments)
    }

    @Test func theVibrationStaysOffAfterTheAppStartsAgain() {
        AppSettings(defaults: defaults).vibratesForCollectedSegments = false

        #expect(!AppSettings(defaults: defaults).vibratesForCollectedSegments)
    }
}
