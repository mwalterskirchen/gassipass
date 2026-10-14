//
//  AreaCompletionTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import Testing
@testable import gassipass

/// The tests use an invented area near Dietikon with a long and a short
/// segment, 200 m apart, so that a walk along one does not touch the other.
struct AreaCompletionTests {
    let long = straightSegment(id: "long", area: 9001, startLatitude: 47.400, startLongitude: 8.400, eastMetres: 1000)
    let short = straightSegment(id: "short", area: 9001, startLatitude: 47.402, startLongitude: 8.400, eastMetres: 100)
    let neighbour = straightSegment(id: "neighbour", area: 9002, startLatitude: 47.404, startLongitude: 8.400, eastMetres: 300)
    let area = Area(id: 9001, name: "Testdorf", canton: "ZH", segmentCount: 2, lengthMetres: 1100)
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)

    var engine: CollectionEngine {
        CollectionEngine(segments: [long, short, neighbour])
    }

    func collection(walking segments: [Segment]) throws -> DogCollection {
        var time = start
        let walks = segments.map { segment in
            let track = syntheticTrack(along: segment, startingAt: time)
            time = track.points.last!.timestamp + 3600
            return CollectionEngine.Walk(dogs: ["Bello"], track: track)
        }
        return try #require(engine.rebuild(dogs: ["Bello"], walks: walks)["Bello"])
    }

    @Test func completionIsBasedOnLength() throws {
        let longOnly = try collection(walking: [long]).completion(of: area)
        let shortOnly = try collection(walking: [short]).completion(of: area)

        #expect(abs(longOnly.share - 1000.0 / 1100) < 0.0001)
        #expect(abs(shortOnly.share - 100.0 / 1100) < 0.0001)
    }

    @Test func theNumberOfCollectedSegmentsCountsOnlyTheSegmentsOfTheArea() throws {
        let none = try collection(walking: []).completion(of: area)
        let one = try collection(walking: [short, neighbour]).completion(of: area)
        let both = try collection(walking: [long, short, neighbour]).completion(of: area)

        #expect(none.collectedSegmentCount == 0)
        #expect(one.collectedSegmentCount == 1)
        #expect(both.collectedSegmentCount == 2)
        #expect(both.segmentCount == 2)
    }

    @Test func withTwoRecordsForTheSameDogAndAreaTheEarliestDateCounts() {
        let records = [
            CompletedRecord(dog: "Bello", goal: 9001, date: start + 60),
            CompletedRecord(dog: "Luna", goal: 9001, date: start - 60),
            CompletedRecord(dog: "Bello", goal: 9001, date: start),
        ]

        #expect(CollectionEngine.completedDate(of: 9001, for: "Bello", in: records) == start)
        #expect(CollectionEngine.completedDate(of: 9002, for: "Bello", in: records) == nil)
    }

    @Test func allSegmentsCollectedIsExactly100PercentAlsoWhenTheLengthsDoNotAddUp() {
        let completion = Completion(
            collectedLengthMetres: 99.999_999, lengthMetres: 100, collectedSegmentCount: 3, segmentCount: 3)

        #expect(completion.share == 1)
    }
}
