//
//  AreaStepTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import Foundation
import Testing
@testable import gassipass

/// The steps of the area stamp and the completion at 95%. The tests use an
/// invented area of 1000 m near Dietikon. Its segments are 250, 250, 250, 200
/// and 50 m long and lie about 110 m apart, so that a walk along one does not
/// touch another. The last two segments are one street.
struct AreaStepTests {
    let a = straightSegment(id: "a", fid: 1, area: 9001, startLatitude: 47.400, startLongitude: 8.400, eastMetres: 250)
    let b = straightSegment(id: "b", fid: 2, area: 9001, startLatitude: 47.401, startLongitude: 8.400, eastMetres: 250)
    let c = straightSegment(id: "c", fid: 3, area: 9001, startLatitude: 47.402, startLongitude: 8.400, eastMetres: 250)
    let d = straightSegment(
        id: "d", fid: 4, area: 9001, street: "Kirchweg", startLatitude: 47.403, startLongitude: 8.400, eastMetres: 200)
    let e = straightSegment(
        id: "e", fid: 5, area: 9001, street: "Kirchweg", startLatitude: 47.404, startLongitude: 8.400, eastMetres: 50)
    let area = Area(id: 9001, name: "Stufendorf", canton: "ZH", segmentCount: 5, lengthMetres: 1000)
    let kirchweg = Street(id: Street.ID(area: 9001, name: "Kirchweg"), segmentCount: 2, lengthMetres: 250)
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)

    /// The collection of Bello after one walk along each segment, an hour apart.
    func collection(walking segments: [Segment]) throws -> DogCollection {
        var time = start
        let walks = segments.map { segment in
            let track = syntheticTrack(along: segment, startingAt: time)
            time = track.points.last!.timestamp + 3600
            return CollectionEngine.Walk(dogs: ["Bello"], track: track)
        }
        let engine = CollectionEngine(segments: [a, b, c, d, e])
        return try #require(engine.rebuild(dogs: ["Bello"], walks: walks)["Bello"])
    }

    func collectedAt(_ segment: Segment, in collection: DogCollection) throws -> Date {
        try #require(collection.collected[segment.id]).collectedAt
    }

    // MARK: Completed at 95%

    @Test func anAreaIsCompletedAt95PercentWithTheDateOfTheSegmentThatLiftedItThere() throws {
        let collection = try collection(walking: [a, b, c, d])

        let records = CollectionEngine.completedRecords(
            collections: ["Bello": collection], areas: [area], existing: [])

        #expect(records == [CompletedRecord(dog: "Bello", goal: 9001, date: try collectedAt(d, in: collection))])
    }

    @Test func anAreaBelow95PercentIsNotCompleted() throws {
        let collection = try collection(walking: [a, b, c, e])

        let records = CollectionEngine.completedRecords(
            collections: ["Bello": collection], areas: [area], existing: [])

        #expect(collection.completion(of: area).share == 0.8)
        #expect(records.isEmpty)
    }

    @Test func aStreetStillNeedsEverySegment() throws {
        let most = try collection(walking: [d])
        let all = try collection(walking: [e, d])

        let mostRecords = CollectionEngine.completedRecords(
            collections: ["Bello": most], streets: [kirchweg], existing: [])
        let allRecords = CollectionEngine.completedRecords(
            collections: ["Bello": all], streets: [kirchweg], existing: [])

        #expect(most.completions(of: [kirchweg])[kirchweg.id]?.share == 0.8)
        #expect(mostRecords.isEmpty)
        #expect(allRecords == [CompletedRecord(dog: "Bello", goal: kirchweg.id, date: try collectedAt(d, in: all))])
    }

    // MARK: Steps

    @Test func eachStepHasTheDateOfTheSegmentThatLiftedTheCompletionOverIt() throws {
        let collection = try collection(walking: [a, b, c, d])

        let records = CollectionEngine.stepRecords(collections: ["Bello": collection], areas: [area], existing: [])

        #expect(records == [
            CompletedRecord(dog: "Bello", goal: AreaStepID(area: 9001, step: .entry), date: try collectedAt(a, in: collection)),
            CompletedRecord(dog: "Bello", goal: AreaStepID(area: 9001, step: .quarter), date: try collectedAt(a, in: collection)),
            CompletedRecord(dog: "Bello", goal: AreaStepID(area: 9001, step: .half), date: try collectedAt(b, in: collection)),
            CompletedRecord(
                dog: "Bello", goal: AreaStepID(area: 9001, step: .threeQuarters), date: try collectedAt(c, in: collection)),
        ])
    }

    @Test func theEntryStampHasTheDateOfTheFirstCollectedSegment() throws {
        let collection = try collection(walking: [e, a])

        let dates = try #require(collection.stepDates(of: [area])[9001])

        #expect(dates == [.entry: try collectedAt(e, in: collection), .quarter: try collectedAt(a, in: collection)])
    }

    @Test func anAreaWithNoCollectedSegmentHasNoStep() throws {
        let collection = try collection(walking: [])

        #expect(collection.stepDates(of: [area]).isEmpty)
        #expect(CollectionEngine.stepRecords(collections: ["Bello": collection], areas: [area], existing: []).isEmpty)
    }

    @Test func aStepWithARecordGetsNoNewRecord() throws {
        let collection = try collection(walking: [a, b])
        let existing = [CompletedRecord(dog: "Bello", goal: AreaStepID(area: 9001, step: .entry), date: start - 86_400)]

        let records = CollectionEngine.stepRecords(
            collections: ["Bello": collection], areas: [area], existing: existing)

        #expect(records.map(\.goal.step) == [.quarter, .half])
    }

    // MARK: During the walk

    /// The live walk of Bello along the segments, and what each segment
    /// reached when it became collected.
    func liveWalk(
        along segments: [Segment]
    ) -> [(steps: [AreaStepID: Set<String>], completed: [Area.ID: Set<String>])] {
        let engine = CollectionEngine(segments: [a, b, c, d, e])
        var live = CollectionEngine.LiveWalk(dogs: ["Bello"], collections: [:])
        var time = start
        var reached: [(steps: [AreaStepID: Set<String>], completed: [Area.ID: Set<String>])] = []
        for segment in segments {
            let track = syntheticTrack(along: segment, startingAt: time)
            time = track.points.last!.timestamp + 60
            for point in track.points {
                let newlyCollected = live.add(point, using: engine)
                guard !newlyCollected.isEmpty else { continue }
                reached.append((
                    steps: CollectionEngine.reachedSteps(by: newlyCollected, in: live.collections) { _ in area },
                    completed: CollectionEngine.completedGoals(by: newlyCollected, in: live.collections) { _ in area }))
            }
        }
        return reached
    }

    @Test func duringTheWalkEachSegmentReportsTheStepsThatItReached() {
        let reached = liveWalk(along: [e, a, b, c, d])

        #expect(reached.map(\.steps) == [
            [AreaStepID(area: 9001, step: .entry): ["Bello"]],
            [AreaStepID(area: 9001, step: .quarter): ["Bello"]],
            [AreaStepID(area: 9001, step: .half): ["Bello"]],
            [AreaStepID(area: 9001, step: .threeQuarters): ["Bello"]],
            [:],
        ])
        #expect(reached.map(\.completed) == [[:], [:], [:], [:], [9001: ["Bello"]]])
    }

    /// At 95% the area is completed, so the last segment completes nothing.
    @Test func duringTheWalkACompletedAreaIsReportedOnce() {
        let reached = liveWalk(along: [a, b, c, d, e])

        #expect(reached.map(\.completed) == [[:], [:], [:], [9001: ["Bello"]], [:]])
    }
}
