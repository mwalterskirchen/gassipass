//
//  PinnedAreaTests.swift
//  doggoTests
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import Testing
@testable import doggo

/// The tests use the areas and segments of `CollectionBookFixture`.
struct PinnedAreaTests: CollectionBookFixture {
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
