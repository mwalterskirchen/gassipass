//
//  TrackFilterTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import Foundation
import Testing
@testable import gassipass

struct TrackFilterTests {
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)

    func point(north metres: Double, east: Double = 0, at seconds: TimeInterval, accuracy: Double = 5) -> TrackPoint {
        TrackPoint(latitude: 47.4 + metres / 111_000, longitude: 8.4 + east / 75_300,
                   timestamp: start + seconds, horizontalAccuracy: accuracy)
    }

    /// A walk north at 1.4 m/s with a point every second.
    func walk(seconds: ClosedRange<Int>) -> [TrackPoint] {
        seconds.map { point(north: Double($0) * 1.4, at: Double($0)) }
    }

    @Test func pointsAtWalkingSpeedAllPass() {
        let points = walk(seconds: 0...30)

        #expect(Track(points: points).filteredPoints == points)
    }

    @Test func inaccuratePointsDoNotPass() {
        let inaccurate = [point(north: 240, east: 60, at: 0, accuracy: 1414), point(north: 30, at: 1, accuracy: 25)]
        let points = walk(seconds: 2...10)

        #expect(Track(points: inaccurate + points).filteredPoints == points)
    }

    @Test func aJumpOfOnePointDoesNotPass() {
        let before = walk(seconds: 0...10), after = walk(seconds: 12...20)
        let jump = point(north: 15, east: 40, at: 11, accuracy: 18)

        #expect(Track(points: before + [jump] + after).filteredPoints == before + after)
    }

    @Test func aJumpOfSeveralPointsDoesNotPass() {
        let before = walk(seconds: 0...10), after = walk(seconds: 16...20)
        let jump = (11...15).map { point(north: 15, east: 33, at: Double($0), accuracy: 18) }

        #expect(Track(points: before + jump + after).filteredPoints == before + after)
    }

    @Test func aFastMovementThatLastsPassesAfterThirtySeconds() {
        let before = walk(seconds: 0...10)
        // By car at 50 km/h, with a point every 5 seconds.
        let car = (1...8).map { point(north: 14 + Double($0) * 5 * 13.9, at: 10 + Double($0) * 5) }
        var filter = TrackFilter()
        let passed = (before + car).map { filter.add($0) }

        #expect(passed.prefix(before.count).allSatisfy { $0.count == 1 })
        #expect(passed.dropFirst(before.count).prefix(6).allSatisfy { $0.isEmpty })
        #expect(passed[before.count + 6] == Array(car.prefix(7)))
    }
}
