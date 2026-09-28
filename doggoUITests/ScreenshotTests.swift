//
//  ScreenshotTests.swift
//  doggoUITests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import XCTest

/// Walks through the main screens with the demo data and saves a screenshot
/// of each one to the folder in the environment variable `SCREENSHOT_DIR`.
final class ScreenshotTests: XCTestCase {
    private var folder: URL?

    override func setUpWithError() throws {
        continueAfterFailure = true
        let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? ""
        try XCTSkipIf(path.isEmpty, "No SCREENSHOT_DIR")
        folder = URL(fileURLWithPath: path)
    }

    @MainActor
    func testScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoData", "YES"] + (ProcessInfo.processInfo.environment["APPEARANCE"] == "dark"
            ? ["-AppleInterfaceStyle", "Dark"] : [])
        app.launch()
        sleep(4)
        save(app, "1-home")

        let dietikon = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Dietikon'")).firstMatch
        if dietikon.waitForExistence(timeout: 5) {
            dietikon.tap()
            sleep(2)
            save(app, "2-area")
            app.swipeUp()
            sleep(1)
            save(app, "3-area-streets")
            app.navigationBars.buttons.firstMatch.tap()
        }

        app.tabBars.buttons["Walks"].tap()
        sleep(1)
        save(app, "4-walks")
        let firstWalk = app.cells.firstMatch
        if firstWalk.exists {
            firstWalk.tap()
            sleep(3)
            save(app, "5-walk-detail")
            app.navigationBars.buttons.firstMatch.tap()
        }
        let start = app.buttons["Start Walk"].firstMatch
        if start.exists {
            start.tap()
            sleep(1)
            save(app, "6-start-walk")
            app.buttons["Cancel"].firstMatch.tap()
        }

        app.tabBars.buttons["Dogs"].tap()
        sleep(1)
        save(app, "7-dogs")

        app.tabBars.buttons["Map"].tap()
        sleep(5)
        save(app, "8-map")
        app.swipeLeft()
        sleep(3)
        save(app, "8b-map-moved")

        app.tabBars.buttons["Book"].tap()
        sleep(3)
        save(app, "9-book")

        app.tabBars.buttons["Walks"].tap()
        app.buttons["Start Walk"].firstMatch.tap()
        sleep(1)
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Luna'")).firstMatch.tap()
        app.buttons["Start"].firstMatch.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons
            .matching(NSPredicate(format: "label BEGINSWITH 'Allow'")).firstMatch
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
        }
        sleep(6)
        save(app, "10-walk")
    }

    @MainActor
    private func save(_ app: XCUIApplication, _ name: String) {
        guard let folder else { return }
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
