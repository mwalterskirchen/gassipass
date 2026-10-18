//
//  RingCollectionsTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The rings of `Collections` as the app uses them: the home base of the
/// pack, the ring stamps that an update stores, the level and the ring card.
/// The home base lies at the middle of the long straight segment in
/// Dietikon of the fixture package (`FixturePackage`).
@MainActor
struct RingCollectionsTests {
    let container: ModelContainer
    let context: ModelContext
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let segments: [Segment]
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)
    let pack: Pack
    let bello: Dog
    let luna: Dog
    let home: HomeBase
    /// A place in Oetwil an der Limmat, more than 1 km from the home base.
    let newHome: HomeBase

    init() throws {
        container = try LocalStore.inMemory()
        context = container.mainContext
        pack = Pack(name: "", createdAt: start)
        context.insert(pack)
        bello = Dog(name: "Bello", context: context)
        luna = Dog(name: "Luna", context: context)
        bello.pack = pack
        luna.pack = pack
        segments = try FixturePackage.segments()
        let long = try #require(segments.first { $0.id == CollectionEngineTests.longSegmentID })
        let first = try #require(long.coordinates.first), last = try #require(long.coordinates.last)
        home = HomeBase(latitude: (first.latitude + last.latitude) / 2, longitude: (first.longitude + last.longitude) / 2)
        let far = try #require(segments.first { $0.streetID == Street.ID(area: 246, name: "Karligutweg") })
        newHome = HomeBase(try #require(far.coordinates.first))
        pack.setHomeBase(home, at: start)
        try context.save()
    }

    func collections() -> Collections {
        Collections(
            context: context, packages: MapPackages(urls: [try! FixturePackage.url()]),
            cacheRoot: folder.appending(path: "WalkMatches", directoryHint: .isDirectory))
    }

    /// The segments of ring 1 around the home base.
    func ring1() -> [Segment] {
        let ids = Set(RingSegments(centre: home, segments: segments, radiusMetres: 250).segments.map(\.id))
        return segments.filter { ids.contains($0.id) }.sorted { $0.id < $1.id }
    }

    /// Stores an ended walk along each of the segments, with a minute
    /// between them.
    @discardableResult
    func insertWalk(along segments: [Segment], dogs: [Dog], startingAt start: Date) throws -> Walk {
        var points: [TrackPoint] = []
        var time = start
        for segment in segments {
            let part = syntheticTrack(along: segment, startingAt: time)
            points += part.points
            time = part.points.last!.timestamp + 60
        }
        let walk = Walk(startedAt: start, dogs: dogs, context: context)
        walk.store(Track(points: points))
        walk.endedAt = time
        try context.save()
        return walk
    }

    @Test func aDogThatCompletesItsRingGetsARingStampWithTheDateOfASegmentOfTheWalkAndTheNextRingIsCurrent() async throws {
        let ring1 = ring1()
        try #require(ring1.count > 1)
        let walk = try insertWalk(along: ring1, dogs: [bello], startingAt: start)
        let collections = collections()

        await collections.update()

        let stamps = collections.ringRecords(of: bello.id)
        #expect(stamps.map(\.goal) == [Ring(number: 1, centre: home)])
        let dates = Set(ring1.compactMap { collections.collection(of: bello.id).collected[$0.id]?.collectedAt })
        #expect(dates.contains(try #require(stamps.first).date))
        #expect(try #require(walk.endedAt) >= stamps[0].date)
        #expect(collections.level(of: bello.id) == 1)
        #expect(collections.ringStatus(of: bello.id)?.ring == Ring(number: 2, centre: home))
        #expect(collections.ringRecords(of: luna.id).isEmpty)
        #expect(collections.ringStatus(of: luna.id)?.ring == Ring(number: 1, centre: home))
        // The stamps are saved, so another context of the store sees them.
        let stored = try container.newContext().fetchAll(CompletedRing.self)
        #expect(stored.map(\.ring) == [Ring(number: 1, centre: home)])
        #expect(stored.allSatisfy { $0.dogID == bello.id && $0.radiusMetres == 250 && $0.isWaitingToUpload })
    }

    @Test func theRingCardShowsTheCompletionAndTheNearestNewSegments() async throws {
        let ring1 = ring1()
        try insertWalk(along: [try #require(ring1.first)], dogs: [bello], startingAt: start)
        let collections = collections()

        await collections.update()

        let status = try #require(collections.ringStatus(of: bello.id))
        #expect(status.ring == Ring(number: 1, centre: home))
        #expect(status.completion.collectedSegmentCount == 1)
        #expect(status.completion.segmentCount == ring1.count)
        // The nearest new segment lies in ring 1, which the dog has not
        // completed, and the others reach beyond it.
        let nearest = status.nearestNewSegments
        #expect((2...RingStatus.nearestNewSegmentCount).contains(nearest.count))
        #expect(!nearest.contains { $0.id == ring1[0].id })
        #expect(try #require(nearest.first).nearestDistanceMetres <= 250)
        #expect(nearest.contains { $0.distanceMetres > 250 })
        let distances = nearest.map(\.nearestDistanceMetres)
        #expect(distances == distances.sorted())
    }

    @Test func aPackWithoutAHomeBaseHasNoRings() async throws {
        pack.homeLatitude = nil
        pack.homeLongitude = nil
        try context.save()
        try insertWalk(along: ring1(), dogs: [bello], startingAt: start)
        let collections = collections()

        await collections.update()

        #expect(collections.ringStatus(of: bello.id) == nil)
        #expect(collections.ringRecords(of: bello.id).isEmpty)
    }

    @Test func aHomeBaseOutsideTheMapPackagesStaysAtRing1WithoutSegments() async throws {
        // Bern, far from the segments of the fixture package.
        pack.setHomeBase(HomeBase(latitude: 46.948, longitude: 7.447), at: start + 60)
        try context.save()
        try insertWalk(along: ring1(), dogs: [bello], startingAt: start)
        let collections = collections()

        await collections.update()

        let status = try #require(collections.ringStatus(of: bello.id))
        #expect(status.ring.number == 1)
        #expect(status.completion.segmentCount == 0)
        #expect(status.nearestNewSegments.isEmpty)
        #expect(collections.ringRecords(of: bello.id).isEmpty)
    }

    @Test func aRingStampStaysWhenItsWalkIsDeleted() async throws {
        let walk = try insertWalk(along: ring1(), dogs: [bello], startingAt: start)
        let collections = collections()
        await collections.update()
        let stamps = collections.ringRecords(of: bello.id)

        walk.markDeleted()
        try context.save()
        await collections.update()

        #expect(collections.collection(of: bello.id).collected.isEmpty)
        #expect(collections.ringRecords(of: bello.id) == stamps)
        #expect(collections.ringStatus(of: bello.id)?.ring.number == 2)
    }

    @Test func theLevelStaysWhenTheHomeBaseMovesAndTheDogStartsAgainAtRing1() async throws {
        try insertWalk(along: ring1(), dogs: [bello], startingAt: start)
        let collections = collections()
        await collections.update()

        pack.setHomeBase(newHome, at: start + 86_400)
        try context.save()
        await collections.update()

        #expect(collections.level(of: bello.id) == 1)
        #expect(collections.ringRecords(of: bello.id).map(\.goal) == [Ring(number: 1, centre: home)])
        #expect(collections.ringStatus(of: bello.id)?.ring == Ring(number: 1, centre: newHome))
    }

    @Test func twoRingStampsOfTheSameDogAndRingFromTwoPhonesBecomeOneWithTheEarliestDate() async throws {
        let ring = Ring(number: 1, centre: home)
        let later = CompletedRing(dogID: bello.id, ring: ring, completedAt: start + 60, context: context)
        let earlier = CompletedRing(dogID: bello.id, ring: ring, completedAt: start, context: context)
        let other = CompletedRing(dogID: bello.id, ring: Ring(number: 1, centre: newHome), completedAt: start + 120, context: context)
        try context.save()
        let collections = collections()

        await collections.update()

        #expect(later.deletedAt != nil)
        #expect(earlier.deletedAt == nil)
        #expect(other.deletedAt == nil)
        #expect(Set(collections.ringRecords(of: bello.id).map(\.date)) == [start, start + 120])
        #expect(collections.ringStatus(of: bello.id)?.ring.number == 2)
    }
}
