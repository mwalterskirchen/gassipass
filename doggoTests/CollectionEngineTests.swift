//
//  CollectionEngineTests.swift
//  doggoTests
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import Foundation
import Testing
@testable import doggo

/// The engine tests use a map package that the map build made from the
/// Dietikon fixture (`mapbuild/tests/fixtures`). `make test-package` in
/// `mapbuild/` writes it again.
struct CollectionEngineTests {
    /// A straight segment of a 3m Strasse, about 1034 m long.
    static let longSegmentID = "{6DA8DF50-D734-444F-9083-57E271FABD3A}"

    let segments: [Segment]
    let engine: CollectionEngine
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)
    static let everywhere = CoordinateBox(minLongitude: -180, maxLongitude: 180, minLatitude: -90, maxLatitude: 90)

    init() throws {
        let url = try #require(Bundle(for: FixtureBundle.self)
            .url(forResource: "fixture", withExtension: "sqlite"))
        segments = try MapPackage(url: url).segments(in: Self.everywhere)
        engine = CollectionEngine(segments: segments)
    }

    func segment(_ id: String) throws -> Segment {
        try #require(segments.first { $0.id == id })
    }

    /// A walk along a part of a segment. See `syntheticTrack`.
    func track(
        along segment: Segment, from: Double = 0, to: Double = 1,
        metresPerSecond speed: Double = 1.4, leftMetres offset: Double = 0,
        accuracy: Double = 5, startingAt startTime: Date? = nil
    ) -> Track {
        syntheticTrack(along: segment, from: from, to: to, metresPerSecond: speed, leftMetres: offset,
                       accuracy: accuracy, startingAt: startTime ?? start)
    }

    @Test func aWalkAlongAWholeSegmentCollectsIt() throws {
        let longSegment = try segment(Self.longSegmentID)
        let walk = CollectionEngine.Walk(dogs: ["Bello"], track: track(along: longSegment))

        let collections = engine.rebuild(dogs: ["Bello"], walks: [walk])

        #expect(collections["Bello"]?.collectedSegments.contains(longSegment.id) == true)
    }

    @Test func aWalkAlong80PercentOfASegmentDoesNotCollectIt() throws {
        let longSegment = try segment(Self.longSegmentID)
        let walk = CollectionEngine.Walk(dogs: ["Bello"], track: track(along: longSegment, to: 0.8))

        let collections = engine.rebuild(dogs: ["Bello"], walks: [walk])

        #expect(collections["Bello"]?.collectedSegments.contains(longSegment.id) == false)
    }

    @Test func twoWalksThatEachCoverHalfOfALongSegmentFromOppositeEndsCollectItTogether() throws {
        let longSegment = try segment(Self.longSegmentID)
        let fromStart = CollectionEngine.Walk(dogs: ["Bello"], track: track(along: longSegment, from: 0, to: 0.5))
        let fromEnd = CollectionEngine.Walk(dogs: ["Bello"], track: track(along: longSegment, from: 1, to: 0.5))

        let first = engine.rebuild(dogs: ["Bello"], walks: [fromStart])
        let second = engine.rebuild(dogs: ["Bello"], walks: [fromEnd])
        let both = engine.rebuild(dogs: ["Bello"], walks: [fromStart, fromEnd])

        #expect(first["Bello"]?.collectedSegments.contains(longSegment.id) == false)
        #expect(second["Bello"]?.collectedSegments.contains(longSegment.id) == false)
        #expect(both["Bello"]?.collectedSegments.contains(longSegment.id) == true)
    }

    @Test func aWalkThatContinuesByCarCollectsNothingOnTheCarPart() throws {
        let longSegment = try segment(Self.longSegmentID)
        let walking = track(along: longSegment, from: 0, to: 0.5)
        let driving = track(along: longSegment, from: 0.5, to: 1, metresPerSecond: 50 / 3.6,
                            startingAt: walking.points.last!.timestamp + 1)
        let walk = CollectionEngine.Walk(dogs: ["Bello"], track: Track(points: walking.points + driving.points))

        let collection = try #require(engine.rebuild(dogs: ["Bello"], walks: [walk])["Bello"])

        #expect(!collection.collectedSegments.contains(longSegment.id))
        let covered = try #require(collection.coveredParts[longSegment.id])
        #expect(covered.length < 0.5 * longSegment.lengthMetres + CollectionRules.coverRadiusMetres + 5)
    }

    /// A walk along the whole segment at walking speed, with no points
    /// between `from` and `to`, as shares of its length.
    func trackWithGap(along segment: Segment, from: Double, to: Double) -> Track {
        let before = track(along: segment, from: 0, to: from)
        let gapSeconds = (to - from) * segment.lengthMetres / 1.4
        let after = track(along: segment, from: to, to: 1,
                          startingAt: before.points.last!.timestamp + gapSeconds)
        return Track(points: before.points + after.points)
    }

    @Test func aStraightLineAcrossAGapOf300MetresCoversNothing() throws {
        let longSegment = try segment(Self.longSegmentID)
        let walk = CollectionEngine.Walk(dogs: ["Bello"], track: trackWithGap(along: longSegment, from: 0.35, to: 0.65))

        let collection = try #require(engine.rebuild(dogs: ["Bello"], walks: [walk])["Bello"])

        #expect(!collection.collectedSegments.contains(longSegment.id))
        let covered = try #require(collection.coveredParts[longSegment.id])
        #expect(covered.length < 0.7 * longSegment.lengthMetres + 2 * CollectionRules.coverRadiusMetres + 5)
    }

    @Test func aStraightLineAcrossAGapOf60MetresStillCovers() throws {
        let longSegment = try segment(Self.longSegmentID)
        let gap = 60 / longSegment.lengthMetres
        let walk = CollectionEngine.Walk(dogs: ["Bello"], track: trackWithGap(along: longSegment, from: 0.5, to: 0.5 + gap))

        let collections = engine.rebuild(dogs: ["Bello"], walks: [walk])

        #expect(collections["Bello"]?.coveredParts[longSegment.id]?.intervals.count == 1)
        #expect(collections["Bello"]?.collectedSegments.contains(longSegment.id) == true)
    }

    @Test func aTrack30MetresBesideASegmentDoesNotCollectIt() throws {
        let longSegment = try segment(Self.longSegmentID)
        let beside = CollectionEngine.Walk(dogs: ["Bello"], track: track(along: longSegment, leftMetres: 30))

        let collection = try #require(engine.rebuild(dogs: ["Bello"], walks: [beside])["Bello"])

        #expect(!collection.collectedSegments.contains(longSegment.id))
        #expect(collection.coveredParts[longSegment.id] == nil)
    }

    @Test func aTrack15MetresBesideASegmentCollectsIt() throws {
        let longSegment = try segment(Self.longSegmentID)
        let beside = CollectionEngine.Walk(dogs: ["Bello"], track: track(along: longSegment, leftMetres: 15))

        let collections = engine.rebuild(dogs: ["Bello"], walks: [beside])

        #expect(collections["Bello"]?.collectedSegments.contains(longSegment.id) == true)
    }

    @Test func pointsWithPoorAccuracyAreIgnored() throws {
        let longSegment = try segment(Self.longSegmentID)
        let poor = CollectionEngine.Walk(dogs: ["Bello"], track: track(along: longSegment, accuracy: 35))

        let collection = try #require(engine.rebuild(dogs: ["Bello"], walks: [poor])["Bello"])

        #expect(collection == DogCollection())
    }

    @Test func theSegmentsInTheCoverableBoxesOfAWalkGiveTheSameCollection() throws {
        let longSegment = try segment(Self.longSegmentID)
        let walking = track(along: longSegment, from: 0, to: 0.6)
        let driving = track(along: longSegment, from: 0.6, to: 1, metresPerSecond: 50 / 3.6,
                            startingAt: walking.points.last!.timestamp + 1)
        let walk = CollectionEngine.Walk(dogs: ["Bello"], track: Track(points: walking.points + driving.points))

        let boxes = CollectionEngine.coverableBoxes(of: walk.track)
        // Like the spatial index of the package: the segment's box overlaps a box.
        let segmentsInBoxes = segments.filter { segment in
            let latitudes = segment.coordinates.map(\.latitude), longitudes = segment.coordinates.map(\.longitude)
            return boxes.contains { box in
                longitudes.max()! >= box.minLongitude && longitudes.min()! <= box.maxLongitude
                    && latitudes.max()! >= box.minLatitude && latitudes.min()! <= box.maxLatitude
            }
        }
        let fromBoxes = CollectionEngine(segments: segmentsInBoxes).rebuild(dogs: ["Bello"], walks: [walk])

        #expect(!segmentsInBoxes.isEmpty && segmentsInBoxes.count < segments.count)
        #expect(fromBoxes == engine.rebuild(dogs: ["Bello"], walks: [walk]))
        // The car part adds no box, so no box reaches the far end of the segment.
        let end = try #require(driving.points.last)
        #expect(!boxes.contains { box in
            box.minLongitude <= end.longitude && end.longitude <= box.maxLongitude
                && box.minLatitude <= end.latitude && end.latitude <= box.maxLatitude
        })
    }

    @Test func theAreasOfAPackageHaveTheTotalsOfTheirSegments() throws {
        let url = try #require(Bundle(for: FixtureBundle.self)
            .url(forResource: "fixture", withExtension: "sqlite"))

        let areas = try MapPackage(url: url).areas()

        let dietikon = try #require(areas.first { $0.id == 243 })
        #expect(dietikon.name == "Dietikon")
        #expect(dietikon.canton == "ZH")
        #expect(dietikon.segmentCount == 260)
        #expect(abs(dietikon.lengthMetres - 24_568.94) < 0.01)
        #expect(Set(areas.map(\.id)) == [243, 246, 4040])
    }

    @Test func aDogThatDidNotTakePartInAWalkCollectsNothingFromIt() throws {
        let longSegment = try segment(Self.longSegmentID)
        let walk = CollectionEngine.Walk(dogs: ["Bello"], track: track(along: longSegment))

        let collections = engine.rebuild(dogs: ["Bello", "Luna"], walks: [walk])

        #expect(collections["Bello"]?.collectedSegments.contains(longSegment.id) == true)
        #expect(collections["Luna"] == DogCollection())
    }
}

private final class FixtureBundle {}
