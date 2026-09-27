//
//  PinnedAreaTests.swift
//  doggoTests
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import Testing
@testable import doggo

/// The tests use two invented areas in canton Zürich and one in canton
/// Aargau, with segments far enough apart that a walk along one does not
/// touch another.
struct PinnedAreaTests {
    let long = straightSegment(id: "long", area: 9001, startLatitude: 47.400, startLongitude: 8.400, eastMetres: 1000)
    let short = straightSegment(id: "short", area: 9001, startLatitude: 47.402, startLongitude: 8.400, eastMetres: 100)
    let other = straightSegment(id: "other", area: 9002, startLatitude: 47.404, startLongitude: 8.400, eastMetres: 300)
    let aargau = straightSegment(id: "aargau", area: 9101, startLatitude: 47.406, startLongitude: 8.400, eastMetres: 400)
    let areas = [
        Area(id: 9002, name: "Zelgli", canton: "ZH", segmentCount: 1, lengthMetres: 300),
        Area(id: 9101, name: "Aarau Test", canton: "AG", segmentCount: 1, lengthMetres: 400),
        Area(id: 9001, name: "Äsch", canton: "ZH", segmentCount: 2, lengthMetres: 1100),
    ]
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)

    func collection(walking segments: [Segment]) throws -> DogCollection {
        let engine = CollectionEngine(segments: [long, short, other, aargau])
        let walks = segments.enumerated().map { index, segment in
            CollectionEngine.Walk(
                dogs: ["Bello"], track: syntheticTrack(along: segment, startingAt: start + Double(index) * 86_400))
        }
        return try #require(engine.rebuild(dogs: ["Bello"], walks: walks)["Bello"])
    }

    @Test func theHomeScreenShowsOnlyThePinnedAreasOfAllCantonsByNameWithTheirCompletion() throws {
        let pages = CollectionBook.pinnedPages(
            pinned: [9101, 9001], areas: areas, collection: try collection(walking: [short, aargau]),
            dog: "Bello", records: [CompletedRecord(dog: "Bello", goal: 9101, date: start)])

        #expect(pages.map(\.area.name) == ["Aarau Test", "Äsch"])
        #expect(pages.map(\.completion.collectedSegmentCount) == [1, 1])
        #expect(abs(pages[1].completion.share - 100.0 / 1100) < 0.0001)
        #expect(pages.map(\.completedAt) == [start, nil])
    }

    @Test func anAreaPinnedOnTwoDevicesShowsOnceAndAPinOfAnAreaThatIsNotOnThePhoneShowsNothing() throws {
        let pages = CollectionBook.pinnedPages(
            pinned: [9002, 4242, 9002], areas: areas, collection: try collection(walking: []),
            dog: "Bello", records: [])

        #expect(pages.map(\.area.name) == ["Zelgli"])
    }

    @Test func aWalkInAnAreaThatIsNotPinnedStillCollectsItsSegments() throws {
        let collection = try collection(walking: [other])

        let beforePinning = CollectionBook.pinnedPages(
            pinned: [9001], areas: areas, collection: collection, dog: "Bello", records: [])
        let afterPinning = CollectionBook.pinnedPages(
            pinned: [9001, 9002], areas: areas, collection: collection, dog: "Bello", records: [])

        #expect(beforePinning.map(\.completion.collectedSegmentCount) == [0])
        #expect(afterPinning.map(\.area.name) == ["Äsch", "Zelgli"])
        #expect(afterPinning.map(\.completion.collectedSegmentCount) == [0, 1])
    }
}
