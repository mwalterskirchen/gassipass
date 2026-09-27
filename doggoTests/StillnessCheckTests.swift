//
//  StillnessCheckTests.swift
//  doggoTests
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import Testing
@testable import doggo

struct StillnessCheckTests {
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)

    func point(north metres: Double, at seconds: TimeInterval, accuracy: Double = 5) -> TrackPoint {
        TrackPoint(latitude: 47.4 + metres / 111_200, longitude: 8.4,
                   timestamp: start + seconds, horizontalAccuracy: accuracy)
    }

    @Test func asksOneHourAfterTheStartWhenTheWalkerNeverMoves() {
        var check = StillnessCheck(startedAt: start)
        check.add(point(north: 0, at: 5))
        check.add(point(north: 0, at: 600))

        #expect(check.askAt == start + 3600)
    }

    @Test func asksOneHourAfterTheLastMovement() {
        var check = StillnessCheck(startedAt: start)
        check.add(point(north: 0, at: 5))
        check.add(point(north: 200, at: 300))
        check.add(point(north: 400, at: 600))

        #expect(check.askAt == start + 600 + 3600)
    }

    @Test func gpsNoiseAroundOnePlaceIsNotMovement() {
        var check = StillnessCheck(startedAt: start)
        for (index, metres) in [0, 15, -10, 25, -20, 5].enumerated() {
            check.add(point(north: Double(metres), at: Double(index) * 1200))
        }

        #expect(check.askAt == start + 3600)
    }

    @Test func asksAgainOneHourAfterTheWalkerSaysTheWalkContinues() {
        var check = StillnessCheck(startedAt: start)
        check.add(point(north: 0, at: 5))

        check.walkContinues(at: start + 3700)

        #expect(check.askAt == start + 3700 + 3600)
    }

    @Test func jumpsOfPoorIndoorFixesAreNotMovement() {
        var check = StillnessCheck(startedAt: start)
        check.add(point(north: 0, at: 5))
        check.add(point(north: 150, at: 1200, accuracy: 165))
        check.add(point(north: -120, at: 2400, accuracy: 100))

        #expect(check.askAt == start + 3600)
    }
}
