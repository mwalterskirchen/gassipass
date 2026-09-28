//
//  CollectionBookTests.swift
//  doggoTests
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import Testing
@testable import doggo

/// The tests use the areas and segments of `CollectionBookFixture`.
struct CollectionBookTests: CollectionBookFixture {
    @Test func theBookListsEveryAreaOfTheCantonByNameIncludingAreasWithNoCompletion() throws {
        let pages = CollectionBook.pages(
            canton: "ZH", areas: areas, collection: try collection(walking: [short]), dog: "Bello", records: [])

        #expect(pages.map(\.area.name) == ["Äsch", "Zelgli"])
        #expect(pages.map(\.completion.collectedSegmentCount) == [1, 0])
        #expect(abs(pages[0].completion.share - 100.0 / 1100) < 0.0001)
        #expect(pages[1].completion.share == 0)
    }

    @Test func aPageShowsTheDateOnlyWhenTheDogHasCompletedTheArea() throws {
        let records = [
            CompletedRecord(dog: "Bello", goal: 9002, date: start + 60),
            CompletedRecord(dog: "Bello", goal: 9002, date: start),
            CompletedRecord(dog: "Luna", goal: 9001, date: start),
        ]

        let pages = CollectionBook.pages(
            canton: "ZH", areas: areas, collection: try collection(walking: [other]), dog: "Bello", records: records)

        #expect(pages.map(\.completedAt) == [nil, start])
    }

    @Test func aPageHoldsTheCollectedSegmentsOfItsAreaForTheSmallMap() throws {
        let pages = CollectionBook.pages(
            canton: "ZH", areas: areas, collection: try collection(walking: [long, other, aargau]),
            dog: "Bello", records: [])

        #expect(pages.map(\.collectedFeatures) == [[long.fid], [other.fid]])
    }
}
