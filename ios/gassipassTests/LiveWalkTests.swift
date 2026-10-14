//
//  LiveWalkTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import Foundation
import Testing
@testable import gassipass

/// The live mode takes the points of a walk one by one and uses the same
/// rules as the rebuild mode.
struct LiveWalkTests {
    let segments: [Segment]
    let engine: CollectionEngine
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)

    init() throws {
        segments = try FixturePackage.segments()
        engine = CollectionEngine(segments: segments)
    }

    func segment(_ id: String) throws -> Segment {
        try #require(segments.first { $0.id == id })
    }

    /// Walks along the parts of the segments one after the other, with a
    /// pause of a minute between two parts.
    func track(along parts: [(Segment, from: Double, to: Double)], startingAt startTime: Date) -> Track {
        var points: [TrackPoint] = []
        var time = startTime
        for (segment, from, to) in parts {
            let part = syntheticTrack(along: segment, from: from, to: to, startingAt: time)
            points += part.points
            time = part.points.last!.timestamp + 60
        }
        return Track(points: points)
    }

    @Test func theSegmentsThatTheLiveModeReportsAsCollectedMatchARebuildOfTheSameWalk() throws {
        let long = try segment(CollectionEngineTests.longSegmentID)
        let geigenpeterweg = try segment("{90DD8546-C281-468B-818A-527668010199}")
        let sucherenweg = try segment("{F1EB88F6-87FF-4777-B05A-F995B2F1E7E3}:243:1")
        // Earlier, Luna walked Geigenpeterweg, and Bello walked the first half of the long segment.
        let earlier = [
            CollectionEngine.Walk(dogs: ["Luna"], track: track(along: [(geigenpeterweg, 0, 1)], startingAt: start)),
            CollectionEngine.Walk(dogs: ["Bello"], track: track(along: [(long, 0, 0.5)], startingAt: start + 3600)),
        ]
        let walk = CollectionEngine.Walk(dogs: ["Bello", "Luna"], track: track(
            along: [(long, 1, 0.5), (geigenpeterweg, 0, 1), (sucherenweg, 0, 1)], startingAt: start + 86_400))
        let before = engine.rebuild(dogs: ["Bello", "Luna"], walks: earlier)
        let after = engine.rebuild(dogs: ["Bello", "Luna"], walks: earlier + [walk])

        var live = CollectionEngine.LiveWalk(dogs: ["Bello", "Luna"], collections: before)
        var reported: [String: [Segment.ID]] = [:]
        for point in walk.track.points {
            for (dog, collected) in live.add(point, using: engine) {
                reported[dog, default: []] += collected
            }
        }

        #expect(live.collections == after)
        for dog in ["Bello", "Luna"] {
            let new = after[dog]!.collectedSegments.subtracting(before[dog]!.collectedSegments)
            #expect(reported[dog, default: []].sorted() == new.sorted())
        }
        #expect(reported["Bello", default: []].contains(long.id))
        #expect(reported["Bello", default: []].contains(geigenpeterweg.id))
        #expect(!reported["Luna", default: []].contains(long.id))
        #expect(!reported["Luna", default: []].contains(geigenpeterweg.id))
        #expect(reported["Luna", default: []].contains(sucherenweg.id))
    }

    @Test func theSegmentsNearAPointAreThoseThatAreNewForAtLeastOneOfTheDogs() {
        // Two segments near the point, 220 m apart, and one segment 1.1 km away.
        let first = straightSegment(id: "first", area: 9001, startLatitude: 47.400, startLongitude: 8.400, eastMetres: 300)
        let second = straightSegment(id: "second", area: 9001, startLatitude: 47.402, startLongitude: 8.400, eastMetres: 300)
        let far = straightSegment(id: "far", area: 9001, startLatitude: 47.410, startLongitude: 8.400, eastMetres: 300)
        let engine = CollectionEngine(segments: [first, second, far])
        // Luna has collected all three segments, Max only the first one, and Rex nothing.
        let walks = [
            CollectionEngine.Walk(dogs: ["Luna", "Max"], track: syntheticTrack(along: first, startingAt: start)),
            CollectionEngine.Walk(dogs: ["Luna"], track: syntheticTrack(along: second, startingAt: start + 3600)),
            CollectionEngine.Walk(dogs: ["Luna"], track: syntheticTrack(along: far, startingAt: start + 7200)),
        ]
        let collections = engine.rebuild(dogs: ["Luna", "Max", "Rex"], walks: walks)
        let point = CLLocationCoordinate2D(latitude: 47.400, longitude: 8.402)

        func newSegments(for dogs: Set<String>) -> [Segment.ID] {
            engine.newSegments(near: point, withinMetres: 500, for: dogs, in: collections).map(\.id).sorted()
        }

        #expect(newSegments(for: ["Luna"]) == [])
        #expect(newSegments(for: ["Luna", "Max"]) == ["second"])
        #expect(newSegments(for: ["Luna", "Rex"]) == ["first", "second"])
    }

    @Test func theCurrentAreaIsTheAreaOfTheSegmentNearestToTheWalker() throws {
        // Two segments in a row, 40 m apart, in two areas.
        let here = straightSegment(id: "here", area: 9001, startLatitude: 47.400, startLongitude: 8.400, eastMetres: 300)
        let there = straightSegment(id: "there", area: 9002, startLatitude: 47.400, startLongitude: 8.4045, eastMetres: 300)
        let engine = CollectionEngine(segments: [here, there])
        let hereArea = Area(id: 9001, name: "Testdorf", canton: "ZH", segmentCount: 1, lengthMetres: 300)
        // The walk starts 1.1 km away from both segments.
        let away = TrackPoint(latitude: 47.410, longitude: 8.400, timestamp: start - 3600, horizontalAccuracy: 5)
        let alongHere = syntheticTrack(along: here, startingAt: start)
        let alongThere = syntheticTrack(along: there, startingAt: alongHere.points.last!.timestamp + 30)

        var live = CollectionEngine.LiveWalk(dogs: ["Bello"], collections: [:])
        _ = live.add(away, using: engine)
        let areaAway = live.currentArea
        for point in alongHere.points {
            _ = live.add(point, using: engine)
        }
        let areaHere = live.currentArea
        let completionHere = try #require(live.collections["Bello"]).completion(of: hereArea)
        for point in alongThere.points {
            _ = live.add(point, using: engine)
        }

        #expect(areaAway == nil)
        #expect(areaHere == 9001)
        #expect(completionHere.share == 1)
        #expect(live.currentArea == 9002)
    }
}
