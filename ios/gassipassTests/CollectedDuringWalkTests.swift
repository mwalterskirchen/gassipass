//
//  CollectedDuringWalkTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import Foundation
import Testing
@testable import gassipass

/// The number of segments that became collected during a walk. The tests
/// use the areas and segments of `CollectionBookFixture`.
struct CollectedDuringWalkTests: CollectionBookFixture {
    /// A walk of the dogs along each part, one after the other, with a
    /// minute between them. Each part is a segment and the share of it that
    /// the walk covers.
    func walk(
        _ parts: [(segment: Segment, to: Double)], dogs: Set<String> = ["Bello"], startingAt start: Date
    ) -> CollectionEngine.Walk<String> {
        var points: [TrackPoint] = []
        var time = start
        for part in parts {
            let track = syntheticTrack(along: part.segment, to: part.to, startingAt: time)
            points += track.points
            time = track.points.last!.timestamp + 60
        }
        return CollectionEngine.Walk(dogs: dogs, track: Track(points: points))
    }

    func rebuild(_ walks: [CollectionEngine.Walk<String>], dogs: Set<String> = ["Bello"]) -> [String: DogCollection] {
        CollectionEngine(segments: [long, short, other, aargau]).rebuild(dogs: dogs, walks: walks)
    }

    /// From the first to the last point of the walk.
    func time(of walk: CollectionEngine.Walk<String>) -> ClosedRange<Date> {
        walk.track.points.first!.timestamp...walk.track.points.last!.timestamp
    }

    @Test func aWalkCountsTheSegmentsThatBecameCollectedDuringItAndNotThoseOfEarlierWalks() throws {
        let first = walk([(long, 1)], startingAt: start)
        let second = walk([(long, 1), (short, 1), (other, 1)], startingAt: start + 86_400)

        let bello = try #require(rebuild([first, second])["Bello"])

        #expect(bello.collectedSegmentCount(during: time(of: first)) == 1)
        #expect(bello.collectedSegmentCount(during: time(of: second)) == 2)
    }

    @Test func theMapOfAWalkShowsTheSegmentsThatBecameCollectedDuringIt() throws {
        let first = walk([(long, 1)], startingAt: start)
        let second = walk([(long, 1), (short, 1), (other, 1)], startingAt: start + 86_400)

        let bello = try #require(rebuild([first, second])["Bello"])

        #expect(bello.collectedFeatures(during: time(of: first)) == [long.fid])
        #expect(bello.collectedFeatures(during: time(of: second)) == [short.fid, other.fid])
    }

    @Test func whenAnEarlierWalkIsDeletedItsSegmentsCanCountForALaterWalk() throws {
        let first = walk([(long, 1)], startingAt: start)
        let second = walk([(long, 1), (short, 1)], startingAt: start + 86_400)
        let before = try #require(rebuild([first, second])["Bello"])

        let after = try #require(rebuild([second])["Bello"])

        #expect(before.collectedSegmentCount(during: time(of: second)) == 1)
        #expect(after.collectedSegmentCount(during: time(of: second)) == 2)
    }

    @Test func aSegmentThatTwoWalksCoverTogetherCountsForTheWalkThatCompletesIt() throws {
        let first = walk([(long, 0.5)], startingAt: start)
        let second = walk([(long, 1)], startingAt: start + 86_400)

        let bello = try #require(rebuild([first, second])["Bello"])

        #expect(bello.collectedSegmentCount(during: time(of: first)) == 0)
        #expect(bello.collectedSegmentCount(during: time(of: second)) == 1)
    }

    /// Each dog has its own collection, so the same walk can count
    /// differently for each dog that takes part.
    @Test func aWalkWithTwoDogsCountsForEachDogWhatItHasNotCollectedBefore() throws {
        let lunaAlone = walk([(long, 1)], dogs: ["Luna"], startingAt: start)
        let together = walk([(long, 1), (short, 1)], dogs: ["Bello", "Luna"], startingAt: start + 86_400)

        let collections = rebuild([lunaAlone, together], dogs: ["Bello", "Luna"])
        let bello = try #require(collections["Bello"]), luna = try #require(collections["Luna"])

        #expect(bello.collectedSegmentCount(during: time(of: together)) == 2)
        #expect(luna.collectedSegmentCount(during: time(of: together)) == 1)
    }
}
