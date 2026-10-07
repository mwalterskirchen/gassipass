//
//  WalkDistanceTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

struct WalkDistanceTests {
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)

    func point(north metres: Double, east: Double = 0, at seconds: TimeInterval, accuracy: Double = 5) -> TrackPoint {
        TrackPoint(latitude: 47.4 + metres / 111_000, longitude: 8.4 + east / 75_300,
                   timestamp: start + seconds, horizontalAccuracy: accuracy)
    }

    func distance(_ points: [TrackPoint]) -> Double {
        WalkDistance(Track(points: points)).metres
    }

    @Test func aStraightWalkCountsItsFullLength() {
        // A point every 5 m for 200 m, at 1.4 m/s.
        let points = (0...40).map { point(north: Double($0) * 5, at: Double($0) * 5 / 1.4) }

        #expect(abs(distance(points) - 200) < 1)
    }

    @Test func gpsNoiseWhileStandingStillCountsNothing() {
        let points = [0, 4, -3, 6, -5, 2, 7, -6, 1].enumerated().map { index, metres in
            point(north: Double(metres), east: Double(-metres) / 2, at: Double(index))
        }

        #expect(distance(points) == 0)
    }

    @Test func noiseWithinTheAccuracyOfThePointCountsNothing() {
        let points = [0, 14, -12, 16].enumerated().map { index, metres in
            point(north: Double(metres), at: Double(index) * 10, accuracy: 18)
        }

        #expect(distance(points) == 0)
    }

    @Test func pointsWhileTheGpsFindsItsPositionCountNothing() {
        let warmUp = [
            point(north: -120, east: 80, at: 0, accuracy: 65),
            point(north: 60, east: -40, at: 2, accuracy: 35),
            point(north: -25, at: 4, accuracy: 25),
        ]
        let walk = (0...20).map { point(north: Double($0) * 5, at: 6 + Double($0) * 5 / 1.4) }

        #expect(abs(distance(warmUp + walk) - 100) < 1)
    }

    @Test func aCarTripCountsNothing() {
        // 20 m on foot, 1 km by car in one minute, then 40 m on foot again.
        let walkBefore = [point(north: 0, at: 0), point(north: 20, at: 15)]
        let car = (1...6).map { point(north: 20 + Double($0) * 1000 / 6, at: 15 + Double($0) * 10) }
        let walkAfter = [point(north: 1040, at: 90), point(north: 1060, at: 105)]

        #expect(abs(distance(walkBefore + car + walkAfter) - 60) < 1)
    }

    @Test func aJumpOfTheGpsCountsNothing() {
        let points = [
            point(north: 0, at: 0), point(north: 15, at: 11),
            point(north: 15, east: 80, at: 12), point(north: 16, east: 240, at: 13), point(north: 30, at: 22),
        ]

        #expect(abs(distance(points) - 30) < 1)
    }

    /// Stores an ended walk of 200 m whose distance of 999 m comes from the
    /// rules of the version.
    func insertWalk(distanceVersion: Int, into context: ModelContext) throws -> Walk {
        let points = (0...40).map { point(north: Double($0) * 5, at: Double($0) * 5 / 1.4) }
        let walk = Walk(startedAt: start, dogs: [], context: context)
        walk.store(Track(points: points), distanceMetres: 999)
        walk.distanceVersion = distanceVersion
        walk.endedAt = start + 200
        try context.save()
        return walk
    }

    @Test @MainActor func aWalkWithOldRulesGetsItsDistanceAgainAtLaunch() throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let walk = try insertWalk(distanceVersion: 0, into: context)

        try Walk.updateDistances(in: context)

        #expect(abs(walk.distanceMetres - 200) < 1)
        #expect(walk.distanceVersion == WalkDistance.version)
        #expect(!context.hasChanges)
    }

    /// Another phone with a newer build of the app can bring a walk whose
    /// distance comes from newer rules. If this phone calculated it again,
    /// the two phones would replace each other's distance at every launch.
    @Test @MainActor func aWalkWithNewerRulesFromAnotherDeviceKeepsItsDistance() throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let walk = try insertWalk(distanceVersion: WalkDistance.version + 1, into: context)

        try Walk.updateDistances(in: context)

        #expect(walk.distanceMetres == 999)
        #expect(walk.distanceVersion == WalkDistance.version + 1)
    }
}
