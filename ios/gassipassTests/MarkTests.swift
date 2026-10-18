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

/// A walk that covers nearly all of a collected segment gives it a fresh
/// mark (`CollectedSegment.markedAt`).
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

    // MARK: Fading

    /// A collected segment with the feature ID, marked the days before now.
    func collectedSegment(fid: Int, lengthMetres: Double = 100, markedDaysAgo days: Double, now: Date) -> CollectedSegment {
        CollectedSegment(
            fid: fid, area: 9001, street: nil, lengthMetres: lengthMetres, collectedAt: now - 90 * day,
            markedAt: now - days * day)
    }

    @Test func theMapsDrawTheMarksInFiveAgeBandsOfAWeekEachFromTheFreshest() {
        let now = start + 100 * day
        var collection = DogCollection()
        for (fid, days) in [(1, 0.5), (2, 6.9), (3, 8.0), (4, 16.0), (5, 27.0), (6, 29.0), (7, 90.0)] {
            collection.collected["s\(fid)"] = collectedSegment(fid: fid, markedDaysAgo: days, now: now)
        }

        let marks = MarkedFeatures(collections: [collection], at: now)

        #expect(marks.bands == [[1, 2], [3], [4], [5], [6, 7]])
        #expect(marks.all == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test func withSeveralDogsTheMapsDrawTheSegmentsThatEveryDogCollectedWithTheOldestMark() {
        let now = start + 100 * day
        var bello = DogCollection(), luna = DogCollection()
        bello.collected["both"] = collectedSegment(fid: 1, markedDaysAgo: 1, now: now)
        luna.collected["both"] = collectedSegment(fid: 1, markedDaysAgo: 20, now: now)
        bello.collected["bello"] = collectedSegment(fid: 2, markedDaysAgo: 1, now: now)

        let marks = MarkedFeatures(collections: [bello, luna], at: now)

        #expect(marks.bands == [[], [], [1], [], []])
    }

    @Test func theMarkedShareIsTheShareOfTheCollectedLengthInTheRingMarkedInTheLast28Days() {
        let now = start + 100 * day
        let home = HomeBase(latitude: 47.4, longitude: 8.4)
        /// A segment that runs east, with its midpoint the distance north of the home base.
        func segment(_ id: String, fid: Int, northMetres: Double, lengthMetres: Double) -> Segment {
            let latitude = home.latitude + northMetres / LineInMetres.metresPerDegreeLatitude
            let west = lengthMetres / 2 / LineInMetres.metresPerDegreeLongitude(atLatitude: latitude)
            return straightSegment(
                id: id, fid: fid, area: 9001, startLatitude: latitude, startLongitude: home.longitude - west,
                eastMetres: lengthMetres)
        }
        let rings = RingSegments(
            centre: home,
            segments: [
                segment("fresh", fid: 1, northMetres: 50, lengthMetres: 100),
                segment("faded", fid: 2, northMetres: 100, lengthMetres: 300),
                segment("new", fid: 3, northMetres: 150, lengthMetres: 200),
                // Beyond ring 1.
                segment("outside", fid: 4, northMetres: 300, lengthMetres: 500),
            ],
            radiusMetres: 350)
        var collection = DogCollection()
        collection.collected["fresh"] = collectedSegment(fid: 1, lengthMetres: 100, markedDaysAgo: 27, now: now)
        collection.collected["faded"] = collectedSegment(fid: 2, lengthMetres: 300, markedDaysAgo: 29, now: now)
        collection.collected["outside"] = collectedSegment(fid: 4, lengthMetres: 500, markedDaysAgo: 1, now: now)

        let ring = Ring(number: 1, centre: home)

        #expect(rings.markedShare(of: ring, for: collection, at: now) == 0.25)
        #expect(rings.markedShare(of: ring, for: DogCollection(), at: now) == 0)
    }
}
