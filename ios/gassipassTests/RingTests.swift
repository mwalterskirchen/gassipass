//
//  RingTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import CoreLocation
import Foundation
import Testing
@testable import gassipass

/// The rings around a home base, the level and the proposal of a home base.
/// The tests use invented segments near Dietikon that run east, each with
/// its midpoint straight north of the home base, and collections that they
/// build without walks.
struct RingTests {
    let home = HomeBase(latitude: 47.4, longitude: 8.4)
    let oldHome = HomeBase(latitude: 47.41, longitude: 8.41)
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)

    /// A segment that runs east, with its midpoint the distance north of the
    /// home base.
    func segment(_ id: String, fid: Int, northMetres: Double, lengthMetres: Double = 100) -> Segment {
        let latitude = home.latitude + northMetres / LineInMetres.metresPerDegreeLatitude
        let west = lengthMetres / 2 / LineInMetres.metresPerDegreeLongitude(atLatitude: latitude)
        return straightSegment(
            id: id, fid: fid, area: 9001, startLatitude: latitude, startLongitude: home.longitude - west,
            eastMetres: lengthMetres)
    }

    /// A collection that holds the segments, collected at the dates.
    func collection(_ collected: [(Segment, Date)]) -> DogCollection {
        var collection = DogCollection()
        for (segment, date) in collected {
            collection.collected[segment.id] = CollectedSegment(
                fid: segment.fid, area: segment.area, street: nil, lengthMetres: segment.lengthMetres,
                collectedAt: date)
        }
        return collection
    }

    // MARK: Rings

    @Test func theRadiiGrowFromRing1At250MetresAndDoubleEverySecondRing() {
        let radii = (1...10).map { Ring(number: $0, centre: home).radiusMetres }

        #expect(radii == [250, 350, 500, 700, 1000, 1400, 2000, 2800, 4000, 5600])
    }

    @Test func aSegmentBelongsToEachRingThatHoldsItsMidpoint() {
        let near = segment("near", fid: 1, northMetres: 100)
        // It starts 180 m north of the home base, inside ring 1, and its
        // midpoint lies 260 m north, outside ring 1.
        let north = Segment(
            id: "north", fid: 2, area: 9001, wayClass: "2m Weg", street: nil, lengthMetres: 160,
            coordinates: [180.0, 340.0].map {
                CLLocationCoordinate2D(
                    latitude: home.latitude + $0 / LineInMetres.metresPerDegreeLatitude, longitude: home.longitude)
            })
        let far = segment("far", fid: 3, northMetres: 400)

        let rings = RingSegments(centre: home, segments: [far, north, near], radiusMetres: 350)

        #expect(rings.segments(of: Ring(number: 1, centre: home)).map(\.id) == ["near"])
        #expect(rings.segments(of: Ring(number: 2, centre: home)).map(\.id) == ["near", "north"])
    }

    @Test func aDogCompletesARingAt95PercentWithTheDateOfTheSegmentThatLiftedItThere() {
        let a = segment("a", fid: 1, northMetres: 50, lengthMetres: 400)
        let b = segment("b", fid: 2, northMetres: 120, lengthMetres: 400)
        let c = segment("c", fid: 3, northMetres: 180, lengthMetres: 150)
        let d = segment("d", fid: 4, northMetres: 240, lengthMetres: 50)
        let rings = RingSegments(centre: home, segments: [a, b, c, d], radiusMetres: 250)
        let bello = collection([(a, start), (c, start + 7200), (b, start + 3600)])
        let luna = collection([(a, start), (b, start + 3600), (d, start + 7200)])

        let records = CollectionEngine.ringRecords(
            collections: ["Bello": bello, "Luna": luna], around: rings, existing: [])

        #expect(rings.completion(of: Ring(number: 1, centre: home), for: bello).share == 0.95)
        #expect(rings.completion(of: Ring(number: 1, centre: home), for: luna).share == 0.85)
        #expect(records == [CompletedRecord(dog: "Bello", goal: Ring(number: 1, centre: home), date: start + 7200)])
    }

    @Test func aRingWithARecordGetsNoSecondRecord() {
        let a = segment("a", fid: 1, northMetres: 50)
        let rings = RingSegments(centre: home, segments: [a], radiusMetres: 350)
        let existing = [CompletedRecord(dog: "Bello", goal: Ring(number: 1, centre: home), date: start)]

        let records = CollectionEngine.ringRecords(
            collections: ["Bello": collection([(a, start + 60)])], around: rings, existing: existing)

        // Ring 2 holds the same segment, so the dog completes it too.
        #expect(records == [CompletedRecord(dog: "Bello", goal: Ring(number: 2, centre: home), date: start + 60)])
    }

    @Test func aRingWithoutSegmentsIsNotCompleted() {
        let rings = RingSegments(centre: home, segments: [], radiusMetres: 250)

        let records = CollectionEngine.ringRecords(collections: ["Bello": DogCollection()], around: rings, existing: [])

        #expect(records.isEmpty)
    }

    @Test func theCurrentRingIsTheRingAfterTheHighestRingStampAroundTheHomeBase() {
        let records = [
            CompletedRecord(dog: "Bello", goal: Ring(number: 1, centre: home), date: start),
            CompletedRecord(dog: "Bello", goal: Ring(number: 2, centre: oldHome), date: start),
            CompletedRecord(dog: "Luna", goal: Ring(number: 2, centre: home), date: start),
        ]

        #expect(CollectionEngine.currentRing(of: "Bello", around: home, records: records).number == 2)
        #expect(CollectionEngine.currentRing(of: "Bello", around: oldHome, records: records).number == 3)
        #expect(CollectionEngine.currentRing(of: "Rex", around: home, records: records).number == 1)
    }

    /// Ring 1 can hold private ways that the dog cannot walk, so that it
    /// stays below 95% while ring 2 reaches it. The card then moves on.
    @Test func aRingBelowARingStampIsNotTheCurrentRing() {
        let records = [CompletedRecord(dog: "Luna", goal: Ring(number: 2, centre: home), date: start)]

        #expect(CollectionEngine.currentRing(of: "Luna", around: home, records: records).number == 3)
    }

    @Test func aRingWithoutSegmentsIsSkippedWhenARingBeyondItHoldsSegments() {
        // No midpoint lies within 250 m, so ring 1 is empty.
        let rings = RingSegments(
            centre: home, segments: [segment("a", fid: 1, northMetres: 300)], radiusMetres: 500)

        #expect(CollectionEngine.currentRing(of: "Bello", around: home, records: [], skippingEmptyIn: rings).number == 2)
    }

    @Test func withoutAnySegmentAroundTheHomeBaseTheCurrentRingStaysRing1() {
        let rings = RingSegments(centre: home, segments: [], radiusMetres: 500)

        #expect(CollectionEngine.currentRing(of: "Bello", around: home, records: [], skippingEmptyIn: rings).number == 1)
    }

    @Test func theLevelIsTheHighestRingOfTheRingStampsAroundAnyHomeBase() {
        let records = [
            CompletedRecord(dog: "Bello", goal: Ring(number: 1, centre: home), date: start),
            CompletedRecord(dog: "Bello", goal: Ring(number: 4, centre: oldHome), date: start),
            CompletedRecord(dog: "Luna", goal: Ring(number: 6, centre: home), date: start),
        ]

        #expect(CollectionEngine.level(of: "Bello", records: records) == 4)
        #expect(CollectionEngine.level(of: "Rex", records: records) == 0)
    }

    @Test func theNearestNewSegmentsAreTheSegmentsNotCollectedNearestToTheHomeBase() {
        let segments = (1...5).map { segment("s\($0)", fid: $0, northMetres: Double($0) * 40) }
        let rings = RingSegments(centre: home, segments: segments.reversed(), radiusMetres: 250)
        let bello = collection([(segments[0], start), (segments[2], start)])

        let nearest = rings.nearestNewSegments(for: bello, count: 2)

        #expect(nearest.map(\.id) == ["s2", "s4"])
        #expect(abs(nearest[0].nearestDistanceMetres - 80) < 0.5)
    }

    @Test func theNearestNewSegmentIsTheOneWhoseNearestPointLiesNearestToTheHomeBase() {
        // A long segment that passes 30 m north of the home base, with its
        // midpoint about 200 m away, and a short one with its midpoint 60 m
        // away.
        let latitude = home.latitude + 30 / LineInMetres.metresPerDegreeLatitude
        let long = straightSegment(
            id: "long", fid: 1, area: 9001, startLatitude: latitude,
            startLongitude: home.longitude - 30 / LineInMetres.metresPerDegreeLongitude(atLatitude: latitude),
            eastMetres: 460)
        let short = segment("short", fid: 2, northMetres: 60, lengthMetres: 20)
        let rings = RingSegments(centre: home, segments: [short, long], radiusMetres: 250)

        let nearest = rings.nearestNewSegments(for: DogCollection(), count: 2)

        #expect(nearest.map(\.id) == ["long", "short"])
        #expect(abs(nearest[0].nearestDistanceMetres - 30) < 0.5)
        #expect(rings.segments.map(\.id) == ["short", "long"])
    }

    @Test func twoCentresWithinAMillionthOfADegreeAreTheSameHomeBase() {
        #expect(HomeBase(latitude: 47.400_000_2, longitude: 8.399_999_9) == home)
        #expect(HomeBase(latitude: 47.400_01, longitude: 8.4) != home)
    }

    // MARK: Proposal of the home base

    /// A point the distances north and east of the home base.
    func place(northMetres: Double, eastMetres: Double = 0) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: home.latitude + northMetres / LineInMetres.metresPerDegreeLatitude,
            longitude: home.longitude + eastMetres / LineInMetres.metresPerDegreeLongitude(atLatitude: home.latitude))
    }

    @Test func withoutWalksTheAppProposesNoHomeBase() {
        #expect(HomeBase.proposal(fromStarts: []) == nil)
    }

    @Test func theStartOfTheFirstWalkIsTheProposal() {
        #expect(HomeBase.proposal(fromStarts: [place(northMetres: 0)]) == home)
    }

    @Test func thePlaceWhereMostWalksStartIsTheProposalWithStartsWithin100MetresCountedAsOnePlace() throws {
        let starts = [
            place(northMetres: 2000), place(northMetres: 2030),
            place(northMetres: 0), place(northMetres: 60), place(northMetres: 30, eastMetres: 40),
            place(northMetres: 5000),
        ]

        let proposal = try #require(HomeBase.proposal(fromStarts: starts))

        let distance = CLLocation(latitude: proposal.latitude, longitude: proposal.longitude)
            .distance(from: CLLocation(latitude: home.latitude, longitude: home.longitude))
        #expect(distance < 50)
    }
}
