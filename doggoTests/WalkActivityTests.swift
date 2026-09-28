//
//  WalkActivityTests.swift
//  doggoTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import Testing
@testable import doggo

/// The Live Activity shows a change in the game at once, and a longer
/// distance alone only after a while.
struct WalkActivityTests {
    typealias Content = WalkActivityAttributes.ContentState

    let lastUpdate = Date(timeIntervalSinceReferenceDate: 812_000_000)
    let shown = Content(
        distanceMetres: 1000, areaName: "Dietikon",
        completions: [.init(dogName: "Bello", share: 0.2)], collectedSegmentCount: 3)

    @Test func theFirstContentAlwaysShows() {
        #expect(WalkActivity.needsUpdate(from: nil, to: shown, lastUpdate: lastUpdate, now: lastUpdate))
    }

    @Test func aLongerDistanceWaitsForTheUpdateInterval() {
        var content = shown
        content.distanceMetres = 1010
        let soon = lastUpdate + WalkActivity.distanceUpdateInterval - 1
        let later = lastUpdate + WalkActivity.distanceUpdateInterval
        #expect(!WalkActivity.needsUpdate(from: shown, to: content, lastUpdate: lastUpdate, now: soon))
        #expect(WalkActivity.needsUpdate(from: shown, to: content, lastUpdate: lastUpdate, now: later))
    }

    @Test func theSameContentNeverShowsAgain() {
        let later = lastUpdate + WalkActivity.distanceUpdateInterval * 10
        #expect(!WalkActivity.needsUpdate(from: shown, to: shown, lastUpdate: lastUpdate, now: later))
    }

    @Test func aChangeInTheGameShowsAtOnce() {
        var newArea = shown
        newArea.areaName = "Schlieren"
        var newCompletion = shown
        newCompletion.completions = [.init(dogName: "Bello", share: 0.21)]
        var newSegment = shown
        newSegment.collectedSegmentCount = 4
        newSegment.distanceMetres = 1010

        for content in [newArea, newCompletion, newSegment] {
            #expect(WalkActivity.needsUpdate(from: shown, to: content, lastUpdate: lastUpdate, now: lastUpdate + 1))
        }
    }
}
