//
//  TrackTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import Testing
@testable import gassipass

struct TrackTests {
    @Test func storedTrackReadsBackTheSameRawPoints() throws {
        let track = Track(points: [
            TrackPoint(latitude: 47.4028, longitude: 8.4012,
                       timestamp: Date(timeIntervalSinceReferenceDate: 812_000_000.25), horizontalAccuracy: 4.5),
            TrackPoint(latitude: 47.4031, longitude: 8.4019,
                       timestamp: Date(timeIntervalSinceReferenceDate: 812_000_003.75), horizontalAccuracy: 12),
        ])

        let readBack = try Track(data: track.data)

        #expect(readBack == track)
    }

    @Test func distanceOfAWalkAtWalkingSpeedIsTheLengthOfTheLineThroughAllPoints() {
        let start = Date(timeIntervalSinceReferenceDate: 812_000_000)
        // 0.001° north is about 111.2 m, then 0.001° east at 47.4° N is about 75.4 m.
        let track = Track(points: [
            TrackPoint(latitude: 47.400, longitude: 8.400, timestamp: start, horizontalAccuracy: 5),
            TrackPoint(latitude: 47.401, longitude: 8.400, timestamp: start + 60, horizontalAccuracy: 5),
            TrackPoint(latitude: 47.401, longitude: 8.401, timestamp: start + 120, horizontalAccuracy: 5),
        ])

        #expect(abs(track.distanceMetres - 186.6) < 1)
    }
}
