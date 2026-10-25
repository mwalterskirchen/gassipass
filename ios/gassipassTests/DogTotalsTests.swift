//
//  DogTotalsTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import Foundation
import Testing
@testable import gassipass

/// The tests use the areas and segments of `PassportFixture`.
struct DogTotalsTests: PassportFixture {
    @Test func theTotalsCountTheCompletedAreasAndStreets() {
        let totals = DogTotals(
            dog: "Bello",
            areaRecords: [CompletedRecord(dog: "Bello", goal: 9002, date: start)],
            streetRecords: [
                CompletedRecord(dog: "Bello", goal: Street.ID(area: 9001, name: "Hauptstrasse"), date: start),
                CompletedRecord(dog: "Bello", goal: Street.ID(area: 9002, name: "Hauptstrasse"), date: start),
            ])

        #expect(totals.completedAreaCount == 1)
        #expect(totals.completedStreetCount == 2)
    }

    @Test func aDogWithNoRecordsHasNothingCompleted() {
        let totals = DogTotals(dog: "Bello", areaRecords: [], streetRecords: [])

        #expect(totals == DogTotals(completedAreaCount: 0, completedStreetCount: 0))
    }

    /// With two devices there can be two records for the same dog and goal.
    @Test func twoRecordsOfTheSameGoalCountOnceAndRecordsOfOtherDogsDoNotCount() {
        let street = Street.ID(area: 9001, name: "Hauptstrasse")
        let totals = DogTotals(
            dog: "Bello",
            areaRecords: [
                CompletedRecord(dog: "Bello", goal: 9002, date: start),
                CompletedRecord(dog: "Bello", goal: 9002, date: start + 60),
                CompletedRecord(dog: "Luna", goal: 9001, date: start),
            ],
            streetRecords: [
                CompletedRecord(dog: "Bello", goal: street, date: start),
                CompletedRecord(dog: "Bello", goal: street, date: start + 60),
                CompletedRecord(dog: "Luna", goal: Street.ID(area: 9002, name: "Hauptstrasse"), date: start),
            ])

        #expect(totals.completedAreaCount == 1)
        #expect(totals.completedStreetCount == 1)
    }
}
