//
//  ScreenshotTests.swift
//  gassipassUITests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import XCTest

/// Walks through the main screens with the demo data and saves a screenshot
/// of each one to the folder in the environment variable `SCREENSHOT_DIR`.
///
/// Only the scheme "gassipass Screenshots" runs it, so that the tests of the
/// scheme "gassipass" stay fast:
/// `TEST_RUNNER_SCREENSHOT_DIR=<folder> xcodebuild test -scheme "gassipass Screenshots" ...`
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
        // The collections of the demo walks take a few seconds to match.
        sleep(8)
        save(app, "1-home")

        let distance = app.buttons.containing(NSPredicate(format: "label CONTAINS 'this week'")).firstMatch
        if distance.waitForExistence(timeout: 5) {
            distance.tap()
            sleep(1)
            save(app, "1b-distance")
            app.buttons["Earlier"].firstMatch.tap()
            sleep(1)
            let sunday = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH 'Sunday'")).firstMatch
            if sunday.exists {
                sunday.tap()
                sleep(1)
            }
            save(app, "1b2-distance-last-week")
            app.buttons["Weeks"].firstMatch.tap()
            sleep(1)
            save(app, "1c-distance-weeks")
            app.buttons["Months"].firstMatch.tap()
            sleep(1)
            save(app, "1d-distance-months")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

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

        app.swipeUp()
        let huettikon = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Hüttikon'")).firstMatch
        if huettikon.waitForExistence(timeout: 5) {
            huettikon.tap()
            sleep(2)
            save(app, "2b-completed-area")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // Start Walk shows only on the Home tab.
        let start = app.buttons["Start Walk"].firstMatch
        if start.exists {
            start.tap()
            sleep(1)
            save(app, "6-start-walk")
            app.buttons["Cancel"].firstMatch.tap()
        }

        app.tabBars.buttons["Walks"].tap()
        sleep(1)
        save(app, "4-walks")
        let filter = app.navigationBars.buttons["Dog"].firstMatch
        if filter.exists {
            filter.tap()
            app.buttons["Luna"].firstMatch.tap()
            sleep(1)
            save(app, "4b-walks-of-one-dog")
            filter.tap()
            app.buttons["All Dogs"].firstMatch.tap()
            sleep(1)
        }
        // A walk row by its dog, because the first cell is the header of
        // the month.
        let firstWalk = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Bello'")).firstMatch
        if firstWalk.exists {
            firstWalk.tap()
            sleep(3)
            save(app, "5-walk-detail")
            let changeDogs = app.buttons["Change Dogs"].firstMatch
            if changeDogs.exists {
                changeDogs.tap()
                sleep(1)
                save(app, "5b-walk-dogs")
                app.buttons["Cancel"].firstMatch.tap()
                sleep(1)
            }
            app.navigationBars.buttons.firstMatch.tap()
        }

        app.tabBars.buttons["Dogs"].tap()
        sleep(1)
        save(app, "7-dogs")
        let rex = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Rex'")).firstMatch
        if rex.exists {
            rex.tap()
            sleep(1)
            save(app, "7b-edit-dog")
            app.buttons["Cancel"].firstMatch.tap()
            sleep(1)
        }

        app.tabBars.buttons["Map"].tap()
        sleep(5)
        save(app, "8-map")
        app.swipeLeft()
        sleep(3)
        save(app, "8b-map-moved")

        app.tabBars.buttons["Book"].tap()
        sleep(3)
        save(app, "9-book")

        app.tabBars.buttons["Home"].tap()
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
        // Stop the walk, because iOS relaunches an app with a walk in
        // progress after the test, and then without the demo data.
        app.buttons["Stop Walk"].firstMatch.press(forDuration: 2)
        sleep(1)
    }

    @MainActor
    private func save(_ app: XCUIApplication, _ name: String) {
        guard let folder else { return }
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
