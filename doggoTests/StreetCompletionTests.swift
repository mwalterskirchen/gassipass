//
//  StreetCompletionTests.swift
//  doggoTests
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import Testing
@testable import doggo

/// The tests use an invented area near Dietikon with a street of a long and
/// a short segment, a segment of another street and a segment with no name,
/// 200 m apart, so that a walk along one does not touch another. The area
/// next to it has a street with the same name.
struct StreetCompletionTests {
    let long = straightSegment(
        id: "long", area: 9001, street: "Bahnhofstrasse", startLatitude: 47.400, startLongitude: 8.400, eastMetres: 1000)
    let short = straightSegment(
        id: "short", area: 9001, street: "Bahnhofstrasse", startLatitude: 47.402, startLongitude: 8.400, eastMetres: 100)
    let other = straightSegment(
        id: "other", area: 9001, street: "Kirchweg", startLatitude: 47.404, startLongitude: 8.400, eastMetres: 200)
    let unnamed = straightSegment(
        id: "unnamed", area: 9001, startLatitude: 47.406, startLongitude: 8.400, eastMetres: 300)
    let neighbour = straightSegment(
        id: "neighbour", area: 9002, street: "Bahnhofstrasse", startLatitude: 47.408, startLongitude: 8.400, eastMetres: 400)

    let bahnhofstrasse = Street(
        id: Street.ID(area: 9001, name: "Bahnhofstrasse"), segmentCount: 2, lengthMetres: 1100)
    let kirchweg = Street(id: Street.ID(area: 9001, name: "Kirchweg"), segmentCount: 1, lengthMetres: 200)
    let neighbourBahnhofstrasse = Street(
        id: Street.ID(area: 9002, name: "Bahnhofstrasse"), segmentCount: 1, lengthMetres: 400)
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)

    var engine: CollectionEngine {
        CollectionEngine(segments: [long, short, other, unnamed, neighbour])
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

    @Test func streetCompletionIsBasedOnLength() throws {
        let longOnly = try collection(walking: [long]).completions(of: [bahnhofstrasse])[bahnhofstrasse.id]
        let shortOnly = try collection(walking: [short]).completions(of: [bahnhofstrasse])[bahnhofstrasse.id]

        #expect(try abs(#require(longOnly).share - 1000.0 / 1100) < 0.0001)
        #expect(try abs(#require(shortOnly).share - 100.0 / 1100) < 0.0001)
        #expect(longOnly?.collectedSegmentCount == 1)
        #expect(longOnly?.segmentCount == 2)
    }

    @Test func theSameNameInTheNextAreaIsAnotherStreet() throws {
        let completions = try collection(walking: [neighbour, unnamed, other])
            .completions(of: [bahnhofstrasse, kirchweg, neighbourBahnhofstrasse])

        #expect(completions[bahnhofstrasse.id]?.collectedSegmentCount == 0)
        #expect(completions[kirchweg.id]?.share == 1)
        #expect(completions[neighbourBahnhofstrasse.id]?.share == 1)
    }

    @Test func theFirstTimeStreetCompletionReaches100PercentTheEngineCreatesACompletedRecordWithTheDate() throws {
        let afterLong = try ["Bello": collection(walking: [long])]
        let afterBoth = try ["Bello": collection(walking: [long, short])]
        let shortCollectedAt = try #require(afterBoth["Bello"]?.collected["short"]?.collectedAt)

        #expect(CollectionEngine.completedRecords(collections: afterLong, streets: [bahnhofstrasse], existing: [])
            .isEmpty)
        #expect(CollectionEngine.completedRecords(collections: afterBoth, streets: [bahnhofstrasse], existing: [])
            == [CompletedRecord(dog: "Bello", goal: bahnhofstrasse.id, date: shortCollectedAt)])
    }

    @Test func anExistingCompletedStreetRecordStaysWhenTheCompletionLaterFallsBelow100Percent() throws {
        let existing = CompletedRecord(dog: "Bello", goal: bahnhofstrasse.id, date: start - 86_400)
        // A new map release adds a segment to the street that the dog has not walked yet.
        let added = straightSegment(
            id: "added", area: 9001, street: "Bahnhofstrasse", startLatitude: 47.410, startLongitude: 8.400,
            eastMetres: 200)
        let longerStreet = Street(id: bahnhofstrasse.id, segmentCount: 3, lengthMetres: 1300)
        let walks = [long, short].map {
            CollectionEngine.Walk(dogs: ["Bello"], track: syntheticTrack(along: $0, startingAt: start))
        }

        let collections = CollectionEngine(segments: [long, short, added]).rebuild(dogs: ["Bello"], walks: walks)

        #expect(try #require(collections["Bello"]).completions(of: [longerStreet])[longerStreet.id]!.share < 1)
        #expect(CollectionEngine.completedRecords(collections: collections, streets: [longerStreet], existing: [existing])
            == [existing])
    }

    @Test func aStreetThatIsCompletedAgainGetsNoSecondRecord() throws {
        let existing = CompletedRecord(dog: "Bello", goal: bahnhofstrasse.id, date: start - 86_400)
        let collections = try ["Bello": collection(walking: [long, short])]

        #expect(CollectionEngine.completedRecords(collections: collections, streets: [bahnhofstrasse], existing: [existing])
            == [existing])
    }

    @Test func theAreaScreenListsTheStreetsOfTheAreaByNameWithCompletionAndTheDateIfCompleted() throws {
        let records = [
            CompletedRecord(dog: "Bello", goal: kirchweg.id, date: start),
            CompletedRecord(dog: "Luna", goal: bahnhofstrasse.id, date: start),
        ]

        let streets = CollectionBook.streets(
            of: 9001, streets: [neighbourBahnhofstrasse, kirchweg, bahnhofstrasse],
            collection: try collection(walking: [other, short]), dog: "Bello", records: records)

        #expect(streets.map(\.street.name) == ["Bahnhofstrasse", "Kirchweg"])
        #expect(streets.map(\.completion.collectedSegmentCount) == [1, 1])
        #expect(streets.map(\.completedAt) == [nil, start])
    }
}
