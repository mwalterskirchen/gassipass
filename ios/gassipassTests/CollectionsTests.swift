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
    let bello: Dog
    let luna: Dog

    init() throws {
        container = try LocalStore.inMemory()
        context = container.mainContext
        bello = Dog(name: "Bello", context: context)
        luna = Dog(name: "Luna", context: context)
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
        collections.collection(of: dog.id).collectedSegments
    }

    /// Stores an ended walk with the track and the dogs.
    @discardableResult
    func insertWalk(_ track: Track, dogs: [Dog]) throws -> Walk {
        let walk = Walk(startedAt: try #require(track.points.first).timestamp, dogs: dogs, context: context)
        walk.store(track)
        walk.endedAt = try #require(track.points.last).timestamp
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

        first.markDeleted()
        second.markDeleted()
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

        walk.changeDogs(to: [luna])
        try context.save()
        await collections.update()

        #expect(!collected(by: bello, in: collections).contains(long.id))
        #expect(collected(by: luna, in: collections).contains(long.id))
    }

    // MARK: Completed records

    /// The record has the date of the segment that lifted the completion to
    /// 95%: the collected length up to that date reaches 95%, and the
    /// collected length before it does not.
    @Test func aDogThatCompletesAnAreaGetsOneRecordWithTheDateOfTheSegmentThatLiftedItTo95Percent() async throws {
        let oetwil = segments.filter { $0.area == 246 }
        try insertWalk(track(along: oetwil, startingAt: start), dogs: [bello])
        let collections = collections()

        await collections.update()
        await collections.update()

        let collectedInOetwil = collections.collection(of: bello.id).collected.values
            .filter { $0.area == 246 }
        let length = try #require(collections.areas[246]).lengthMetres
        let completedAt = try #require(bello.completedAreas?.first?.completedAt)
        func share(_ isIncluded: (Date) -> Bool) -> Double {
            collectedInOetwil.filter { isIncluded($0.collectedAt) }.reduce(0) { $0 + $1.lengthMetres } / length
        }
        #expect(collectedInOetwil.count == collections.areas[246]?.segmentCount)
        #expect(bello.completedAreas?.map(\.area) == [246])
        #expect(share { $0 <= completedAt } >= 0.95)
        #expect(share { $0 < completedAt } < 0.95)
        #expect(luna.completedAreas?.isEmpty == true)
        // The record is saved, so another context of the store sees it.
        #expect(try container.newContext().fetchAll(CompletedArea.self).count == 1)
    }

    @Test func aCompletedAreaStaysWhenItsWalkIsDeleted() async throws {
        let walk = try insertWalk(track(along: segments.filter { $0.area == 246 }, startingAt: start), dogs: [bello])
        let collections = collections()
        await collections.update()

        walk.markDeleted()
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
            == collections.collection(of: bello.id).collected[street[1].id]?.collectedAt)
        // The record is saved, so another context of the store sees it.
        #expect(try container.newContext().fetchAll(CompletedStreet.self)
            .filter { $0.area == 243 && $0.street == "Sucherenweg" }.count == 1)
    }

    @Test func aCompletedStreetStaysWhenItsWalkIsDeleted() async throws {
        let street = try sucherenweg()
        let walk = try insertWalk(track(along: street, startingAt: start), dogs: [bello])
        let collections = collections()
        await collections.update()

        walk.markDeleted()
        try context.save()
        await collections.update()

        #expect(collected(by: bello, in: collections).isEmpty)
        #expect(sucherenwegRecords(of: bello).count == 1)
    }

    /// A deleted record stays in the store, so that the deletion uploads.
    @Test func twoRecordsOfTheSameDogAndGoalFromTwoPhonesBecomeOneWithTheEarliestDate() async throws {
        let early = start
        let late = start + 86_400
        let sucherenweg = Street.ID(area: 243, name: "Sucherenweg")
        _ = CompletedArea(dog: bello, area: 246, completedAt: late, context: context)
        _ = CompletedArea(dog: bello, area: 246, completedAt: early, context: context)
        _ = CompletedArea(dog: luna, area: 246, completedAt: late, context: context)
        _ = CompletedStreet(dog: bello, street: sucherenweg, completedAt: early, context: context)
        _ = CompletedStreet(dog: bello, street: sucherenweg, completedAt: late, context: context)
        try context.save()

        await collections().update()

        let other = container.newContext()
        let allAreas = try other.fetchAll(CompletedArea.self)
        let areas = allAreas.filter { $0.deletedAt == nil }
        #expect(areas.count == 2)
        #expect(areas.first { $0.dog?.name == "Bello" }?.completedAt == early)
        #expect(areas.first { $0.dog?.name == "Luna" }?.completedAt == late)
        #expect(allAreas.count == 3)
        #expect(allAreas.allSatisfy { $0.isWaitingToUpload })
        let streets = try other.fetchAll(CompletedStreet.self).filter { $0.deletedAt == nil }
        #expect(streets.map(\.completedAt) == [early])
    }

    @Test func twoRecordsWithTheSameDateKeepTheSameRecordOnEveryPhone() async throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000A"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000B"))
        let second = CompletedArea(dog: bello, area: 246, completedAt: start, context: context)
        second.id = secondID
        let first = CompletedArea(dog: bello, area: 246, completedAt: start, context: context)
        first.id = firstID
        try context.save()

        await collections().update()

        let other = container.newContext()
        #expect(try other.fetchAll(CompletedArea.self).filter { $0.deletedAt == nil }.map(\.id) == [firstID])
    }

    // MARK: Area steps

    /// The steps of the stamp of the area that the collection book shows for the dog.
    func steps(of dog: Dog, in area: Area.ID, _ collections: Collections) throws -> [StampStep: Date] {
        let canton = try #require(collections.areas[area]).canton
        return try #require(collections.pages(canton: canton, for: dog).first { $0.area.id == area }).steps
    }

    /// The segments of Oetwil an der Limmat, the shortest first.
    func oetwil() -> [Segment] {
        segments.filter { $0.area == 246 }.sorted { $0.lengthMetres < $1.lengthMetres }
    }

    @Test func theWalksOfADogGiveItTheStepsOfTheAreaWithTheDatesOfTheirSegments() async throws {
        let oetwil = oetwil()
        try insertWalk(syntheticTrack(along: oetwil[0], startingAt: start), dogs: [bello])
        try insertWalk(track(along: Array(oetwil.dropFirst()), startingAt: start + 86_400), dogs: [bello])
        let collections = collections()

        await collections.update()

        let reached = try steps(of: bello, in: 246, collections)
        let collected = collections.collection(of: bello.id).collected.values.filter { $0.area == 246 }
        #expect(Set(reached.keys) == Set(StampStep.allCases))
        #expect(reached[.entry] == collected.map(\.collectedAt).min())
        #expect(try #require(reached[.entry]) < start + 86_400)
        #expect(reached[.completed] == bello.completedAreas?.first?.completedAt)
        let dates = StampStep.allCases.compactMap { reached[$0] }
        #expect(dates == dates.sorted())
        #expect(try steps(of: luna, in: 246, collections).isEmpty)
        // The steps are saved, so another context of the store sees them.
        let stored = try container.newContext().fetchAll(AreaStep.self)
        #expect(Set(stored.compactMap(\.stampStep)) == Set(StampStep.areaSteps))
        #expect(stored.allSatisfy { $0.dogID == bello.id && $0.area == 246 && $0.isWaitingToUpload })
    }

    @Test func theStepsStayWhenTheirWalksAreDeleted() async throws {
        let walk = try insertWalk(track(along: oetwil(), startingAt: start), dogs: [bello])
        let collections = collections()
        await collections.update()
        let reached = try steps(of: bello, in: 246, collections)

        walk.markDeleted()
        try context.save()
        await collections.update()

        #expect(collected(by: bello, in: collections).isEmpty)
        #expect(try steps(of: bello, in: 246, collections) == reached)
        #expect(try container.newContext().fetchAll(AreaStep.self).count == StampStep.areaSteps.count)
    }

    @Test func twoStepsOfTheSameDogAreaAndStepFromTwoPhonesBecomeOneWithTheEarliestDate() async throws {
        let early = start
        let late = start + 86_400
        _ = AreaStep(dog: bello, area: 246, step: .half, reachedAt: late, context: context)
        _ = AreaStep(dog: bello, area: 246, step: .half, reachedAt: early, context: context)
        _ = AreaStep(dog: bello, area: 246, step: .quarter, reachedAt: late, context: context)
        _ = AreaStep(dog: luna, area: 246, step: .half, reachedAt: late, context: context)
        try context.save()
        let collections = collections()

        await collections.update()

        #expect(try steps(of: bello, in: 246, collections) == [.quarter: late, .half: early])
        #expect(try steps(of: luna, in: 246, collections) == [.half: late])
        let all = try container.newContext().fetchAll(AreaStep.self)
        #expect(all.count == 4)
        #expect(all.filter { $0.deletedAt != nil }.map(\.reachedAt) == [late])
        #expect(all.allSatisfy { $0.isWaitingToUpload })
    }

    // MARK: Stamps from earlier walks

    @Test func theFirstUpdateCountsTheNewStampsOfEachDogFromItsEarlierWalksOnce() async throws {
        try insertWalk(track(along: oetwil(), startingAt: start), dogs: [bello])
        let defaults = emptyDefaults()
        let first = Collections(
            context: context, packages: MapPackages(urls: [fixture]), cacheRoot: nil, defaults: defaults)

        await first.update()

        // The four steps of Oetwil an der Limmat and its full stamp.
        #expect(first.earlierStamps == [bello.id: 5])
        // A launch in the background can end before the count shows, and
        // the next launch shows it.
        let second = Collections(
            context: context, packages: MapPackages(urls: [fixture]), cacheRoot: nil, defaults: defaults)
        await second.update()
        #expect(second.earlierStamps == [bello.id: 5])
        second.noteEarlierStampsShown()
        #expect(second.earlierStamps == nil)
        let third = Collections(
            context: context, packages: MapPackages(urls: [fixture]), cacheRoot: nil, defaults: defaults)
        await third.update()
        #expect(third.earlierStamps == nil)
    }

    @Test func aPhoneWithoutStampsFromEarlierWalksShowsNoCount() async throws {
        let collections = Collections(
            context: context, packages: MapPackages(urls: [fixture]), cacheRoot: nil, defaults: emptyDefaults())

        await collections.update()

        #expect(collections.earlierStamps == nil)
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
        #expect(totals.completedAreaCount == 1)
        #expect(totals.completedStreetCount >= Set(oetwil.compactMap(\.streetID)).count)
        #expect(totals.completedStreetCount == bello.completedStreets?.count)
        #expect(collections.totals(of: luna)
            == DogTotals(completedAreaCount: 0, completedStreetCount: 0))
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

        second.changeDogs(to: [bello, luna])
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
        #expect(second.collection(of: bello.id) == first.collection(of: bello.id))
    }

    /// Removes the stored matches of the walks and makes the track of the
    /// walk unreadable, so that a walk that is matched again collects nothing.
    /// The stored history stays.
    func removeMatches(andTrackOf walk: Walk) throws {
        let root = folder.appending(path: "WalkMatches")
        for version in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for file in try FileManager.default.contentsOfDirectory(at: version, includingPropertiesForKeys: nil)
            where file.lastPathComponent != "history" {
                try FileManager.default.removeItem(at: file)
            }
        }
        walk.trackData = Data([0xFF])
        try context.save()
    }

    @Test func anUpdateAfterANewWalkDoesNotMatchTheEarlierWalksAgain() async throws {
        let long = try long(), far = try far()
        let earlier = try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        let collections = collections()
        await collections.update()
        try removeMatches(andTrackOf: earlier)

        try insertWalk(syntheticTrack(along: far, startingAt: start + 86_400), dogs: [bello])
        await collections.update()

        #expect(collected(by: bello, in: collections).isSuperset(of: [long.id, far.id]))
    }

    @Test func theFirstUpdateAfterARelaunchAddsANewWalkToTheStoredHistory() async throws {
        let long = try long(), far = try far()
        let earlier = try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        await collections().update()
        try removeMatches(andTrackOf: earlier)

        try insertWalk(syntheticTrack(along: far, startingAt: start + 86_400), dogs: [bello])
        let relaunched = collections()
        await relaunched.update()

        #expect(collected(by: bello, in: relaunched).isSuperset(of: [long.id, far.id]))
    }

    /// For example a walk from the phone of another member, which arrives
    /// after a later walk of this phone.
    @Test func aWalkThatArrivesAfterALaterWalkGivesTheCollectionsOfARebuild() async throws {
        let long = try long()
        let hour = 3600.0
        try insertWalk(syntheticTrack(along: long, from: 0, to: 0.5, startingAt: start), dogs: [bello, luna])
        try insertWalk(syntheticTrack(along: long, from: 0.4, to: 1, startingAt: start + 2 * hour), dogs: [bello])
        let collections = collections()
        await collections.update()

        try insertWalk(syntheticTrack(along: long, from: 1, to: 0.5, startingAt: start + hour), dogs: [bello, luna])
        await collections.update()

        let rebuilt = Collections(context: context, packages: MapPackages(urls: [fixture]), cacheRoot: nil)
        await rebuilt.update()
        #expect(collections.byDog == rebuilt.byDog)
        let collected = try #require(collections.collection(of: bello.id).collected[long.id])
        #expect(collected.collectedAt < start + 2 * hour)
    }

    @Test func aDogAddedToAWalkAfterAnUpdateCollectsItsSegments() async throws {
        let long = try long()
        let walk = try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        let collections = collections()
        await collections.update()

        walk.changeDogs(to: [bello, luna])
        try context.save()
        await collections.update()

        #expect(collected(by: luna, in: collections).contains(long.id))
        #expect(collected(by: bello, in: collections).contains(long.id))
    }

    // MARK: Stored collections

    /// The app shows the numbers at launch, before the first update ends.
    @Test func aRelaunchShowsTheStoredCollectionsBeforeItsFirstUpdate() async throws {
        let long = try long()
        let walk = try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        let first = collections()
        await first.update()

        let second = collections()

        #expect(second.collection(of: bello.id) == first.collection(of: bello.id))
        #expect(collected(by: bello, in: second).contains(long.id))
        #expect(second.totals(of: bello) != nil)
        #expect(second.totals(of: luna) != nil)
        #expect(second.collectedSegmentCount(during: walk, of: bello) == first.collectedSegmentCount(during: walk, of: bello))
    }

    @Test func aRelaunchWithTheSameWalksMatchesNoWalk() async throws {
        let long = try long()
        let walk = try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        await collections().update()

        // Without its track and its stored match, a walk that is matched
        // again collects nothing.
        try FileManager.default.removeItem(at: folder.appending(path: "WalkMatches"))
        walk.trackData = Data([0xFF])
        try context.save()
        let second = collections()
        await second.update()

        #expect(collected(by: bello, in: second).contains(long.id))
    }

    @Test func anUpdateStoresTheCollectionsForTheNextLaunch() async throws {
        let long = try long(), far = try far()
        let first = try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        try insertWalk(syntheticTrack(along: far, startingAt: start + 3600), dogs: [bello])
        await collections().update()

        first.markDeleted()
        try context.save()
        let second = collections()
        await second.update()
        let third = collections()

        #expect(!collected(by: bello, in: third).contains(long.id))
        #expect(collected(by: bello, in: third).contains(far.id))
        #expect(third.collection(of: bello.id) == second.collection(of: bello.id))
    }

    /// After the first store, a store compares the collections with the
    /// stored ones, so a new walk writes only the rows of its segments.
    @Test func anUpdateAfterANewWalkWritesOnlyTheRowsOfItsSegments() async throws {
        let long = try long(), far = try far()
        try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        let collections = collections()
        await collections.update()
        let segmentsBefore = collections.collection(of: bello.id).coveredParts.count
        try insertWalk(syntheticTrack(along: far, startingAt: start + 3_600), dogs: [bello])
        let saved = SavedRows()
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: context, queue: nil
        ) { notification in
            saved.note(notification)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await collections.update()

        let newSegments = collections.collection(of: bello.id).coveredParts.count - segmentsBefore
        #expect(newSegments > 0)
        #expect(saved.inserted == newSegments)
        #expect(saved.updated == 0)
        #expect(saved.deleted == 0)
    }

    /// A store that fails can leave a row that the collections do not
    /// have. The relaunch shows it, and the next update deletes it.
    @Test func aStoredRowThatTheCollectionsDoNotHaveLeavesWithTheNextUpdate() async throws {
        let long = try long(), far = try far()
        try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        await collections().update()
        var parts = CoveredParts()
        parts.add(0...10)
        let stray = WalkedSegment(dogID: bello.id, segmentID: far.id)
        stray.coveredParts = parts.data
        context.insert(stray)
        try context.save()
        let relaunched = collections()
        let shownBeforeTheUpdate = relaunched.collection(of: bello.id).coveredParts.keys.contains(far.id)
        try insertWalk(syntheticTrack(along: long, startingAt: start + 3_600), dogs: [luna])

        await relaunched.update()

        #expect(shownBeforeTheUpdate)
        #expect(!relaunched.collection(of: bello.id).coveredParts.keys.contains(far.id))
        #expect(try storedRows() == relaunched.byDog.values.map(\.coveredParts.count).reduce(0, +))
        #expect(collections().byDog == relaunched.byDog)
    }

    /// A row of a dog that the stored collections do not know is not in the
    /// collections at all, so the next update checks every row.
    @Test func aStoredRowOfAnUnknownDogLeavesWithTheNextUpdate() async throws {
        let long = try long()
        try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        await collections().update()
        context.insert(WalkedSegment(dogID: UUID(), segmentID: long.id))
        try context.save()
        let relaunched = collections()
        try insertWalk(syntheticTrack(along: long, startingAt: start + 3_600), dogs: [luna])

        await relaunched.update()

        let rows = try context.fetch(FetchDescriptor<WalkedSegment>())
        #expect(Set(rows.map(\.dogID)) == [bello.id, luna.id])
        #expect(rows.count == relaunched.byDog.values.map(\.coveredParts.count).reduce(0, +))
        #expect(collections().byDog == relaunched.byDog)
    }

    func storedRows() throws -> Int {
        try context.fetchCount(FetchDescriptor<WalkedSegment>())
    }

    @Test func aRelaunchWithANewMapReleaseShowsTheStoredCollectionsUntilItsUpdateEnds() async throws {
        let long = try long()
        try insertWalk(syntheticTrack(along: long, startingAt: start), dogs: [bello])
        await collections(packages: [try package(release: "2026-01")]).update()

        let newRelease = try package(release: "2026-02", without: long)
        let after = collections(packages: [newRelease])
        let collectedBefore = collected(by: bello, in: after)
        await after.update()

        #expect(collectedBefore.contains(long.id))
        #expect(!collected(by: bello, in: after).contains(long.id))
        #expect(!collected(by: bello, in: collections(packages: [newRelease])).contains(long.id))
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
        collections.collection(of: dog.id).completion(of: try #require(collections.areas[area]))
    }

    @Test func aNewMapReleaseWithAnAddedSegmentLowersTheCompletionButKeepsTheCompletedRecordAndTheSteps() async throws {
        let far = try far()
        let oetwil = segments.filter { $0.area == 246 && $0.id != far.id }
        try insertWalk(track(along: oetwil, startingAt: start), dogs: [bello])
        let before = collections(packages: [try package(release: "2026-01", without: far)])
        await before.update()
        let completedBefore = try completion(of: bello, in: 246, before)
        #expect(completedBefore.share >= 1)
        #expect(bello.completedAreas?.map(\.area) == [246])
        let completedAt = bello.completedAreas?.first?.completedAt
        let stepsBefore = try steps(of: bello, in: 246, before)
        #expect(Set(stepsBefore.keys) == Set(StampStep.allCases))

        let after = collections(packages: [try package(release: "2026-02")])
        await after.update()

        let completion = try completion(of: bello, in: 246, after)
        #expect(completion.share < 1)
        #expect(completion.segmentCount == completedBefore.segmentCount + 1)
        #expect(bello.completedAreas?.map(\.area) == [246])
        #expect(bello.completedAreas?.first?.completedAt == completedAt)
        #expect(try steps(of: bello, in: 246, after) == stepsBefore)
        #expect(try container.newContext().fetchAll(AreaStep.self).count == StampStep.areaSteps.count)
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

/// Counts the stored collection rows that each save inserts, updates and
/// deletes.
private final class SavedRows: @unchecked Sendable {
    private(set) var inserted = 0
    private(set) var updated = 0
    private(set) var deleted = 0

    func note(_ notification: Notification) {
        inserted += count(.insertedIdentifiers, in: notification)
        updated += count(.updatedIdentifiers, in: notification)
        deleted += count(.deletedIdentifiers, in: notification)
    }

    private func count(_ key: ModelContext.NotificationKey, in notification: Notification) -> Int {
        let identifiers = notification.userInfo?[key.rawValue] as? [PersistentIdentifier] ?? []
        return identifiers.count { $0.entityName == "WalkedSegment" }
    }
}
