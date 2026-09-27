//
//  AreaCompletionTests.swift
//  doggoTests
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import Testing
@testable import doggo

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

    @Test func theFirstTimeCompletionReaches100PercentTheEngineCreatesACompletedRecordWithTheDateOfThePoint() throws {
        let first = CollectionEngine.Walk(dogs: ["Bello"], track: syntheticTrack(along: short, startingAt: start))
        // A point every 50 m. The stretch that ends at 900 m covers up to
        // 920 m, which is the first time that 90% of the long segment is covered.
        let secondStart = start + 86_400
        let line = LineInMetres(long)
        let second = CollectionEngine.Walk(dogs: ["Bello"], track: Track(points: stride(from: 0.0, through: 1000, by: 50).map {
            line.point(at: $0, leftMetres: 0, accuracy: 5, timestamp: secondStart + $0 / 1.4)
        }))

        let afterFirst = engine.rebuild(dogs: ["Bello"], walks: [first])
        let afterBoth = engine.rebuild(dogs: ["Bello"], walks: [first, second])

        #expect(CollectionEngine.completedRecords(collections: afterFirst, areas: [area], existing: []).isEmpty)
        #expect(CollectionEngine.completedRecords(collections: afterBoth, areas: [area], existing: [])
            == [CompletedRecord(dog: "Bello", area: 9001, date: secondStart + 900 / 1.4)])
    }

    @Test func anExistingCompletedRecordStaysWhenTheCompletionLaterFallsBelow100Percent() throws {
        let existing = CompletedRecord(dog: "Bello", area: 9001, date: start - 86_400)
        // A new map release adds a segment that the dog has not walked yet.
        let added = straightSegment(id: "added", area: 9001, startLatitude: 47.403, startLongitude: 8.400, eastMetres: 200)
        let newRelease = CollectionEngine(segments: [long, short, added])
        let largerArea = Area(id: 9001, name: "Testdorf", canton: "ZH", segmentCount: 3, lengthMetres: 1300)
        let walks = [long, short].map { CollectionEngine.Walk(dogs: ["Bello"], track: syntheticTrack(along: $0, startingAt: start)) }

        let collections = newRelease.rebuild(dogs: ["Bello"], walks: walks)

        #expect(try #require(collections["Bello"]).completion(of: largerArea).share < 1)
        #expect(CollectionEngine.completedRecords(collections: collections, areas: [largerArea], existing: [existing])
            == [existing])
    }

    @Test func anAreaThatIsCompletedAgainGetsNoSecondRecord() throws {
        let existing = CompletedRecord(dog: "Bello", area: 9001, date: start - 86_400)
        let collections = try ["Bello": collection(walking: [long, short])]

        #expect(CollectionEngine.completedRecords(collections: collections, areas: [area], existing: [existing])
            == [existing])
    }

    @Test func withTwoRecordsForTheSameDogAndAreaTheEarliestDateCounts() {
        let records = [
            CompletedRecord(dog: "Bello", area: 9001, date: start + 60),
            CompletedRecord(dog: "Luna", area: 9001, date: start - 60),
            CompletedRecord(dog: "Bello", area: 9001, date: start),
        ]

        #expect(CollectionEngine.completedDate(of: 9001, for: "Bello", in: records) == start)
        #expect(CollectionEngine.completedDate(of: 9002, for: "Bello", in: records) == nil)
    }
}
