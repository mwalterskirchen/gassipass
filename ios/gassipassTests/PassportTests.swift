//
//  PassportTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import Testing
@testable import gassipass

/// The tests use the areas and segments of `PassportFixture`.
struct PassportTests: PassportFixture {
    @Test func theBookListsEveryAreaOfTheCantonByNameIncludingAreasWithNoCompletion() throws {
        let pages = Passport.pages(
            canton: "ZH", areas: areas, collection: try collection(walking: [short]), dog: "Bello", records: [], steps: [])

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

        let pages = Passport.pages(
            canton: "ZH", areas: areas, collection: try collection(walking: [other]), dog: "Bello", records: records, steps: [])

        #expect(pages.map(\.completedAt) == [nil, start])
    }

    @Test func aPageShowsTheEarliestDateOfEachStepOfTheDogAndItsHighestStep() throws {
        let steps = [
            CompletedRecord(dog: "Bello", goal: AreaStepID(area: 9001, step: .entry), date: start),
            CompletedRecord(dog: "Bello", goal: AreaStepID(area: 9001, step: .quarter), date: start + 120),
            CompletedRecord(dog: "Bello", goal: AreaStepID(area: 9001, step: .quarter), date: start + 60),
            CompletedRecord(dog: "Luna", goal: AreaStepID(area: 9002, step: .entry), date: start),
        ]
        let records = [CompletedRecord(dog: "Bello", goal: 9002, date: start)]

        let pages = Passport.pages(
            canton: "ZH", areas: areas, collection: try collection(walking: [long]), dog: "Bello", records: records,
            steps: steps)

        #expect(pages.map(\.steps) == [[.entry: start, .quarter: start + 60], [.completed: start]])
        #expect(pages.map(\.step) == [.quarter, .completed])
    }

    @Test func aPageHoldsTheCollectedSegmentsOfItsAreaForTheSmallMap() throws {
        let pages = Passport.pages(
            canton: "ZH", areas: areas, collection: try collection(walking: [long, other, aargau]),
            dog: "Bello", records: [], steps: [])

        #expect(pages.map(\.collectedFeatures) == [[long.fid], [other.fid]])
    }

    @Test func theBookCanSortTheAreasByCompletionWithTheMostCompletedFirst() throws {
        let pages = Passport.pages(
            canton: "ZH", areas: areas, collection: try collection(walking: [other]), dog: "Bello", records: [], steps: [])

        #expect(Passport.sorted(pages, by: .completion).map(\.area.name) == ["Zelgli", "Äsch"])
        #expect(Passport.sorted(pages, by: .name).map(\.area.name) == ["Äsch", "Zelgli"])
    }

    @Test func areasWithTheSameCompletionAreSortedByName() throws {
        let pages = Passport.pages(
            canton: "ZH", areas: areas, collection: try collection(walking: [aargau]), dog: "Bello", records: [], steps: [])

        #expect(Passport.sorted(pages.reversed(), by: .completion).map(\.area.name) == ["Äsch", "Zelgli"])
    }
}
