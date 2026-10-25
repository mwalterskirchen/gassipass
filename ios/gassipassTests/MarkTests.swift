//
//  MarkTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import CoreLocation
import Foundation
import Testing
@testable import gassipass

/// A walk that covers nearly all of a collected segment gives it a mark
/// (`CollectedSegment.markedAt`), and the maps draw a segment in the shade
/// of its marks of the last four weeks (`MarkedFeatures`).
struct MarkTests {
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)
    let day = 86_400.0
    /// A straight segment of 300 m that runs east.
    let segment = straightSegment(id: "here", area: 9001, startLatitude: 47.400, startLongitude: 8.400, eastMetres: 300)

    @Test func theMarkHasTheTimeOfTheLatestWalkThatCoveredNearlyAllOfTheSegment() throws {
        let engine = CollectionEngine(segments: [segment])
        let first = syntheticTrack(along: segment, startingAt: start)
        let second = syntheticTrack(along: segment, from: 1, to: 0, startingAt: start + 3 * day)

        let collected = try #require(
            engine.rebuild(dogs: ["Bello"], walks: [.init(dogs: ["Bello"], track: first),
                                                    .init(dogs: ["Bello"], track: second)])["Bello"]?
                .collected[segment.id])

        #expect(collected.collectedAt < start + day)
        // The last point of the second walk lies on the segment.
        #expect(collected.markedAt == second.points.last!.timestamp)
    }

    @Test func aWalkAlongHalfOfTheSegmentDoesNotRefreshItsMark() throws {
        let engine = CollectionEngine(segments: [segment])
        let whole = syntheticTrack(along: segment, startingAt: start)
        let half = syntheticTrack(along: segment, to: 0.5, startingAt: start + 3 * day)

        let collected = try #require(
            engine.rebuild(dogs: ["Bello"], walks: [.init(dogs: ["Bello"], track: whole),
                                                    .init(dogs: ["Bello"], track: half)])["Bello"]?
                .collected[segment.id])

        #expect(collected.markedAt == whole.points.last!.timestamp)
    }

    @Test func aSegmentThatTwoWalksCollectTogetherIsMarkedWhenItBecameCollected() throws {
        let engine = CollectionEngine(segments: [segment])
        let fromStart = syntheticTrack(along: segment, to: 0.6, startingAt: start)
        let fromEnd = syntheticTrack(along: segment, from: 1, to: 0.4, startingAt: start + 3 * day)

        let collected = try #require(
            engine.rebuild(dogs: ["Bello"], walks: [.init(dogs: ["Bello"], track: fromStart),
                                                    .init(dogs: ["Bello"], track: fromEnd)])["Bello"]?
                .collected[segment.id])

        #expect(collected.collectedAt > start + 3 * day)
        #expect(collected.markedAt == collected.collectedAt)
    }

    @Test func aWalkThatCrossesASegmentAtAJunctionDoesNotMarkIt() throws {
        // A side way of 200 m runs north from the middle of the segment.
        let middle = segment.coordinates[0].longitude
            + 150 / LineInMetres.metresPerDegreeLongitude(atLatitude: 47.400)
        let side = Segment(
            id: "side", fid: 0, area: 9001, wayClass: "2m Weg", street: nil, lengthMetres: 200,
            coordinates: [CLLocationCoordinate2D(latitude: 47.400, longitude: middle),
                          CLLocationCoordinate2D(latitude: 47.400 + 200 / LineInMetres.metresPerDegreeLatitude,
                                                 longitude: middle)])
        let engine = CollectionEngine(segments: [segment, side])
        let alongSide = syntheticTrack(along: side, startingAt: start)
        let alongSegment = syntheticTrack(along: segment, startingAt: start + 3 * day)

        let collections = engine.rebuild(
            dogs: ["Bello"], walks: [.init(dogs: ["Bello"], track: alongSide),
                                     .init(dogs: ["Bello"], track: alongSegment)])
        let collected = try #require(collections["Bello"]?.collected[side.id])

        // The second walk covers the side way where it starts, and no more.
        #expect(collections["Bello"]?.coveredParts[side.id] != nil)
        #expect(collected.markedAt == alongSide.points.last!.timestamp)
    }

    @Test func theLiveModeReportsTheCollectedSegmentsWhoseMarksTheWalkRefreshes() throws {
        let engine = CollectionEngine(segments: [segment])
        let earlier = CollectionEngine.Walk(dogs: ["Bello"], track: syntheticTrack(along: segment, startingAt: start))
        let walk = CollectionEngine.Walk(
            dogs: ["Bello", "Luna"], track: syntheticTrack(along: segment, from: 1, to: 0, startingAt: start + 3 * day))
        let before = engine.rebuild(dogs: ["Bello", "Luna"], walks: [earlier])

        var live = CollectionEngine.LiveWalk(dogs: ["Bello", "Luna"], collections: before)
        var collected: [String: [Segment.ID]] = [:]
        var refreshed: [String: [Segment.ID]] = [:]
        for point in walk.track.points {
            let change = live.add(point, using: engine)
            change.collected.forEach { collected[$0.key, default: []] += $0.value }
            change.refreshed.forEach { refreshed[$0.key, default: []] += $0.value }
        }

        // Bello had collected the segment, so the walk refreshes its mark
        // once. Luna collects it.
        #expect(refreshed == ["Bello": [segment.id]])
        #expect(collected == ["Luna": [segment.id]])
        #expect(live.collections == engine.rebuild(dogs: ["Bello", "Luna"], walks: [earlier, walk]))
        #expect(live.collections["Bello"]?.collected[segment.id]?.markedAt == walk.track.points.last!.timestamp)
    }

    // MARK: Shades

    /// A collected segment with the feature ID, collected the days before now.
    func collectedSegment(fid: Int, collectedDaysAgo days: Double = 90, now: Date) -> CollectedSegment {
        CollectedSegment(
            fid: fid, area: 9001, street: nil, lengthMetres: 100, collectedAt: now - days * day,
            markedAt: now - days * day)
    }

    /// The times of marks the days before now.
    func marks(daysAgo days: [Double], now: Date) -> [Date] {
        days.map { now - $0 * day }
    }

    @Test func theMapsDrawTheSegmentsInTheShadeOfTheirMarksOfTheLastFourWeeks() {
        let now = start + 100 * day
        var collection = DogCollection()
        for fid in 1...6 {
            collection.collected["s\(fid)"] = collectedSegment(fid: fid, now: now)
        }
        let walkMarks: [Segment.ID: [Date]] = [
            "s2": marks(daysAgo: [3], now: now),
            "s3": marks(daysAgo: [1, 8, 15, 22], now: now),
            "s4": marks(daysAgo: [1, 2, 3, 4, 5, 6], now: now),
            // Older than four weeks.
            "s5": marks(daysAgo: [29, 40], now: now),
            "s6": marks(daysAgo: [1, 29, 40, 50, 60], now: now),
        ]

        let features = MarkedFeatures(dogs: [(collection, walkMarks)], at: now)

        #expect(features.all == [1, 2, 3, 4, 5, 6])
        #expect(features.shades == [[2, 6], [3], [4]])
    }

    /// A segment that two walks collected together has no mark of a walk
    /// alone, but it is new, so it shows as marked once.
    @Test func aSegmentCollectedInTheLastFourWeeksShowsAsMarkedAtLeastOnce() {
        let now = start + 100 * day
        var collection = DogCollection()
        collection.collected["new"] = collectedSegment(fid: 1, collectedDaysAgo: 2, now: now)
        collection.collected["old"] = collectedSegment(fid: 2, collectedDaysAgo: 40, now: now)

        let features = MarkedFeatures(dogs: [(collection, [:])], at: now)

        #expect(features.shades == [[1], [], []])
        #expect(features.all == [1, 2])
    }

    @Test func withSeveralDogsTheMapsDrawTheSegmentsThatEveryDogCollectedInTheShadeOfTheDogThatMarkedThemLeast() {
        let now = start + 100 * day
        var bello = DogCollection(), luna = DogCollection()
        bello.collected["both"] = collectedSegment(fid: 1, now: now)
        luna.collected["both"] = collectedSegment(fid: 1, now: now)
        bello.collected["bello"] = collectedSegment(fid: 2, now: now)

        let features = MarkedFeatures(
            dogs: [
                (bello, ["both": marks(daysAgo: [1, 2, 3, 4, 5], now: now)]),
                (luna, ["both": marks(daysAgo: [1, 2], now: now)]),
            ],
            at: now)

        #expect(features.all == [1])
        #expect(features.shades == [[], [1], []])
    }
}
