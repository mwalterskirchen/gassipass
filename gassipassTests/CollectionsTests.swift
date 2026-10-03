//
//  CollectionsTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The tests of `Collections` as the app uses it: an update reads the dogs
/// and the ended walks from the store and matches them against the fixture
/// package (`FixturePackage`). Each test has its own in-memory store and its
/// own folders.
@MainActor
struct CollectionsTests {
    let container: ModelContainer
    let context: ModelContext
    let fixture: URL
    /// The folder for the files of the test: the stored matches and copies of packages.
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let segments: [Segment]
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)
    let bello = Dog(name: "Bello")
    let luna = Dog(name: "Luna")

    init() throws {
        container = try ModelContainer(
            for: Dog.self, Walk.self, CompletedArea.self, CompletedStreet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context = ModelContext(container)
        context.insert(bello)
        context.insert(luna)
        try context.save()
        fixture = try FixturePackage.url()
        segments = try FixturePackage.segments()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func collections(packages: [URL]? = nil) -> Collections {
        Collections(
            context: context, packages: MapPackages(urls: packages ?? [fixture]),
            cacheRoot: folder.appending(path: "WalkMatches", directoryHint: .isDirectory))
    }

    /// The straight segment in Dietikon, about 1034 m long.
    func long() throws -> Segment {
        try #require(segments.first { $0.id == CollectionEngineTests.longSegmentID })
    }

    /// The segment of Karligutweg in Oetwil an der Limmat, more than 1 km
    /// away from the long segment.
    func far() throws -> Segment {
        try #require(segments.first { $0.streetID == Street.ID(area: 246, name: "Karligutweg") })
    }

    func collected(by dog: Dog, in collections: Collections) -> Set<Segment.ID> {
        collections.collection(of: dog.persistentModelID).collectedSegments
    }

    /// Stores an ended walk with the track and the dogs.
    @discardableResult
    func insertWalk(_ track: Track, dogs: [Dog]) throws -> Walk {
        let walk = Walk(startedAt: try #require(track.points.first).timestamp, dogs: dogs)
        walk.store(track)
        walk.endedAt = try #require(track.points.last).timestamp
        context.insert(walk)
        try context.save()
        return walk
    }

    /// A walk along each of the segments, one after the other, with a minute
    /// between them.
    func track(along segments: [Segment], startingAt start: Date) -> Track {
        var points: [TrackPoint] = []
        var time = start
        for segment in segments {
            let part = syntheticTrack(along: segment, startingAt: time)
            points += part.points
            time = part.points.last!.timestamp + 60
        }
        return Track(points: points)
    }

    // MARK: Collections

    @Test func anUpdateAddsTheSegmentsOfAWalkToTheCollectionsOfItsDogs() async throws {
        let long = try long()
        try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello, luna])
        let collections = collections()

        await collections.update()

        #expect(collected(by: bello, in: collections).contains(long.id))
        #expect(collected(by: luna, in: collections).contains(long.id))
        #expect(collections.areas[243]?.name == "Dietikon")
        #expect(collections.streets[246]?.contains { $0.name == "Karligutweg" } == true)
        #expect(collections.cantons == ["AG", "ZH"])
    }

    @Test func deletingAWalkRemovesItsSegmentsUnlessAnotherWalkCollectedThem() async throws {
        let long = try long(), far = try far()
        let first = try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        let second = try insertWalk(syntheticTrack(along: far, startingAt: start + 3600), dogs: [bello])
        try insertWalk(syntheticTrack(along: long, from: 1, to: 0, startingAt: start + 7200), dogs: [bello])
        let collections = collections()
        await collections.update()

        context.delete(first)
        context.delete(second)
        try context.save()
        await collections.update()

        #expect(collected(by: bello, in: collections).contains(long.id))
        #expect(!collected(by: bello, in: collections).contains(far.id))
    }

    @Test func changingTheDogsOfAWalkMovesItsSegmentsToTheNewDogs() async throws {
        let long = try long()
        let walk = try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        let collections = collections()
        await collections.update()

        walk.dogs = [luna]
        try context.save()
        await collections.update()

        #expect(!collected(by: bello, in: collections).contains(long.id))
        #expect(collected(by: luna, in: collections).contains(long.id))
    }

    // MARK: Completed records

    @Test func aDogThatCompletesAnAreaGetsOneRecordWithTheDateOfItsLastSegment() async throws {
        let oetwil = segments.filter { $0.area == 246 }
        try insertWalk(track(along: oetwil, startingAt: start), dogs: [bello])
        let collections = collections()

        await collections.update()
        await collections.update()

        let collectedInOetwil = collections.collection(of: bello.persistentModelID).collected.values
            .filter { $0.area == 246 }
        #expect(collectedInOetwil.count == collections.areas[246]?.segmentCount)
        #expect(bello.completedAreas?.map(\.area) == [246])
        #expect(bello.completedAreas?.first?.completedAt == collectedInOetwil.map(\.collectedAt).max())
        #expect(luna.completedAreas?.isEmpty == true)
        // The record is saved, so another context of the store sees it.
        #expect(try ModelContext(container).fetch(FetchDescriptor<CompletedArea>()).count == 1)
    }

    @Test func aCompletedAreaStaysWhenItsWalkIsDeleted() async throws {
        let walk = try insertWalk(track(along: segments.filter { $0.area == 246 }, startingAt: start), dogs: [bello])
        let collections = collections()
        await collections.update()

        context.delete(walk)
        try context.save()
        await collections.update()

        #expect(collected(by: bello, in: collections).isEmpty)
        #expect(bello.completedAreas?.map(\.area) == [246])
    }

    /// The completed records of Sucherenweg. A walk along it can also
    /// complete a short street that crosses it.
    func sucherenwegRecords(of dog: Dog) -> [CompletedStreet] {
        (dog.completedStreets ?? []).filter { $0.area == 243 && $0.street == "Sucherenweg" }
    }

    /// The two segments of Sucherenweg in Dietikon.
    func sucherenweg() throws -> [Segment] {
        let street = segments.filter { $0.streetID == Street.ID(area: 243, name: "Sucherenweg") }
        try #require(street.count == 2)
        return street
    }

    @Test func aDogThatCompletesAStreetGetsOneRecordWithTheDateOfItsLastSegment() async throws {
        let street = try sucherenweg()
        try insertWalk(syntheticTrack(along: street[0], startingAt: start), dogs: [bello])
        let collections = collections()
        await collections.update()
        #expect(sucherenwegRecords(of: bello).isEmpty)

        try insertWalk(syntheticTrack(along: street[1], startingAt: start + 86_400), dogs: [bello])
        await collections.update()
        await collections.update()

        let records = sucherenwegRecords(of: bello)
        #expect(records.count == 1)
        #expect(records.first?.completedAt
            == collections.collection(of: bello.persistentModelID).collected[street[1].id]?.collectedAt)
        // The record is saved, so another context of the store sees it.
        #expect(try ModelContext(container).fetch(FetchDescriptor<CompletedStreet>(
            predicate: #Predicate { $0.area == 243 && $0.street == "Sucherenweg" })).count == 1)
    }

    @Test func aCompletedStreetStaysWhenItsWalkIsDeleted() async throws {
        let street = try sucherenweg()
        let walk = try insertWalk(track(along: street, startingAt: start), dogs: [bello])
        let collections = collections()
        await collections.update()

        context.delete(walk)
        try context.save()
        await collections.update()

        #expect(collected(by: bello, in: collections).isEmpty)
        #expect(sucherenwegRecords(of: bello).count == 1)
    }

    // MARK: Totals

    @Test func theTotalsOfADogAreUnknownUntilTheFirstUpdateAlsoForADogWithNoWalks() async throws {
        let oetwil = segments.filter { $0.area == 246 }
        try insertWalk(track(along: oetwil, startingAt: start), dogs: [bello])
        let collections = collections()
        #expect(collections.totals(of: bello) == nil)
        #expect(collections.totals(of: luna) == nil)

        await collections.update()

        let totals = try #require(collections.totals(of: bello))
        #expect(totals.collectedLengthMetres >= oetwil.reduce(0) { $0 + $1.lengthMetres } - 1)
        #expect(totals.completedAreaCount == 1)
        #expect(totals.completedStreetCount >= Set(oetwil.compactMap(\.streetID)).count)
        #expect(totals.completedStreetCount == bello.completedStreets?.count)
        #expect(collections.totals(of: luna)
            == DogTotals(collectedLengthMetres: 0, completedAreaCount: 0, completedStreetCount: 0))
    }

    // MARK: Segments collected during a walk

    /// The count is unknown for a walk that the last update did not build
    /// into the collection of the dog, so that the dashboard does not show
    /// 0 while the update runs.
    @Test func theCountOfAWalkIsUnknownUntilAnUpdateHasBuiltTheWalkIntoTheCollectionOfTheDog() async throws {
        let long = try long(), far = try far()
        let first = try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        let collections = collections()
        #expect(collections.collectedSegmentCount(during: first, of: bello) == nil)

        await collections.update()
        let afterFirst = collected(by: bello, in: collections).count
        #expect(afterFirst > 0)
        #expect(collections.collectedSegmentCount(during: first, of: bello) == afterFirst)

        let second = try insertWalk(syntheticTrack(along: far, startingAt: start + 3600), dogs: [bello])
        #expect(collections.collectedSegmentCount(during: second, of: bello) == nil)
        await collections.update()
        #expect(collections.collectedSegmentCount(during: second, of: bello)
            == collected(by: bello, in: collections).count - afterFirst)

        second.dogs = [bello, luna]
        try context.save()
        #expect(collections.collectedSegmentCount(during: second, of: luna) == nil)
        await collections.update()
        #expect(collections.collectedSegmentCount(during: second, of: luna) == collected(by: luna, in: collections).count)
    }

    // MARK: Stored matches

    @Test func newCollectionsOnTheSameCacheFolderGiveTheSameCollectionsFromTheStoredMatches() async throws {
        let long = try long()
        let walk = try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        let first = collections()
        await first.update()

        // Only a stored match can collect the segment now. The start, the end
        // and the distance of the walk stay, so its match keeps its key.
        walk.trackData = Data([0xFF])
        try context.save()
        let second = collections()
        await second.update()

        #expect(collected(by: bello, in: second).contains(long.id))
        #expect(second.collection(of: bello.persistentModelID) == first.collection(of: bello.persistentModelID))
    }

    /// A walk that has no track data yet, for example from a sync that has
    /// not finished, or whose track data cannot be read.
    @Test(arguments: [nil, Data([0xFF])])
    func aTrackThatCannotBeReadCollectsNothingAndCountsOnceItCanBeRead(trackData: Data?) async throws {
        let long = try long()
        let track = syntheticTrack(along: long, startingAt: start)
        let walk = try insertWalk(track, dogs: [bello])
        walk.trackData = trackData
        try context.save()
        let collections = collections()
        await collections.update()
        #expect(collected(by: bello, in: collections).isEmpty)

        walk.trackData = track.data
        try context.save()
        await collections.update()

        #expect(collected(by: bello, in: collections).contains(long.id))
    }

    // MARK: Map packages

    @Test func aPackageThatCannotOpenKeepsThePreviousCollections() async throws {
        let long = try long(), far = try far()
        let package = try FixturePackage.copy(named: "fixture.sqlite", in: folder)
        try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        let collections = collections(packages: [package])
        await collections.update()

        try FileManager.default.removeItem(at: package)
        try Data("not a map package".utf8).write(to: package)
        try insertWalk(syntheticTrack(along: far, startingAt: start + 3600), dogs: [bello])
        await collections.update()

        #expect(collected(by: bello, in: collections).contains(long.id))
        #expect(!collected(by: bello, in: collections).contains(far.id))
    }

    @Test func aWalkCountsAsSoonAsThePackageOfItsAreaArrivesAlsoWithTheSameMapRelease() async throws {
        let long = try long()
        // A package of another canton: the same map release, but no segments here.
        let other = try FixturePackage.copy(named: "other.sqlite", in: folder, changedBy: "DELETE FROM segments")
        try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        let before = collections(packages: [other])
        await before.update()
        #expect(collected(by: bello, in: before).isEmpty)

        let after = collections(packages: [other, fixture])
        await after.update()

        #expect(collected(by: bello, in: after).contains(long.id))
    }

    // MARK: Map releases

    /// The fixture as the package "zh.sqlite" of another map release,
    /// without the segment if one is given. Each package has its own
    /// folder, so that a new map release is the only change between two
    /// packages.
    func package(release: String, without segment: Segment? = nil) throws -> URL {
        var sql = "UPDATE meta SET value = '\(release)' WHERE key = 'map_release';"
        if let segment {
            sql += """
                UPDATE areas SET segment_count = segment_count - 1, length_m = length_m - \(segment.lengthMetres)
                    WHERE bfs_number = \(segment.area);
                UPDATE streets SET segment_count = segment_count - 1, length_m = length_m - \(segment.lengthMetres)
                    WHERE area = \(segment.area) AND name = '\(segment.street ?? "")';
                DELETE FROM streets WHERE segment_count = 0;
                DELETE FROM segments_index WHERE fid = \(segment.fid);
                DELETE FROM segments WHERE fid = \(segment.fid);
                """
        }
        return try FixturePackage.copy(
            named: "zh.sqlite", in: folder.appending(path: release, directoryHint: .isDirectory), changedBy: sql)
    }

    func completion(of dog: Dog, in area: Area.ID, _ collections: Collections) throws -> Completion {
        collections.collection(of: dog.persistentModelID).completion(of: try #require(collections.areas[area]))
    }

    @Test func aNewMapReleaseWithAnAddedSegmentLowersTheCompletionButKeepsTheCompletedRecord() async throws {
        let far = try far()
        let oetwil = segments.filter { $0.area == 246 && $0.id != far.id }
        try insertWalk(track(along: oetwil, startingAt: start), dogs: [bello])
        let before = collections(packages: [try package(release: "2026-01", without: far)])
        await before.update()
        let completedBefore = try completion(of: bello, in: 246, before)
        #expect(completedBefore.share >= 1)
        #expect(bello.completedAreas?.map(\.area) == [246])
        let completedAt = bello.completedAreas?.first?.completedAt

        let after = collections(packages: [try package(release: "2026-02")])
        await after.update()

        let completion = try completion(of: bello, in: 246, after)
        #expect(completion.share < 1)
        #expect(completion.segmentCount == completedBefore.segmentCount + 1)
        #expect(bello.completedAreas?.map(\.area) == [246])
        #expect(bello.completedAreas?.first?.completedAt == completedAt)
    }

    @Test func aNewMapReleaseWithAnAddedSegmentThatAnOldWalkCoversCollectsTheSegment() async throws {
        let long = try long()
        try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        let before = collections(packages: [try package(release: "2026-01", without: long)])
        await before.update()
        #expect(!collected(by: bello, in: before).contains(long.id))

        let after = collections(packages: [try package(release: "2026-02")])
        await after.update()

        #expect(collected(by: bello, in: after).contains(long.id))
    }

    @Test func aSegmentThatANewMapReleaseRemovesLeavesTheCollection() async throws {
        let long = try long()
        try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        let before = collections(packages: [try package(release: "2026-01")])
        await before.update()
        #expect(collected(by: bello, in: before).contains(long.id))

        let after = collections(packages: [try package(release: "2026-02", without: long)])
        await after.update()

        #expect(!collected(by: bello, in: after).contains(long.id))
    }
}
