//
//  WalkMatchCacheTests.swift
//  doggoTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import Testing
@testable import doggo

struct WalkMatchCacheTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let segment = straightSegment(id: "long", area: 9001, startLatitude: 47.400, startLongitude: 8.400, eastMetres: 1000)
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)

    func key(_ minutes: Double) -> WalkMatchCache.Key {
        WalkMatchCache.Key(startedAt: start.addingTimeInterval(minutes * 60),
                           endedAt: start.addingTimeInterval(minutes * 60 + 900), distanceMetres: 1000)
    }

    func cache(mapRelease: String = "2026-02") throws -> WalkMatchCache {
        let cache = WalkMatchCache(root: root, build: "1", mapRelease: mapRelease)
        #expect(cache.makeFolder(removingOthersIn: root))
        return cache
    }

    func match() -> WalkMatch {
        CollectionEngine(segments: [segment]).match(syntheticTrack(along: segment, startingAt: start))
    }

    @Test func aStoredMatchGivesTheSameCollectionsAsANewMatch() throws {
        let cache = try cache()
        let match = match()

        cache.store(match, for: key(0))
        let stored = try #require(cache.match(for: key(0)))

        #expect(stored == match)
        #expect(CollectionEngine.collections(of: ["Bello"], from: [(dogs: Set(["Bello"]), match: stored)])
            == CollectionEngine(segments: [segment]).rebuild(
                dogs: ["Bello"], walks: [.init(dogs: ["Bello"], track: syntheticTrack(along: segment, startingAt: start))]))
        #expect(stored.entries[segment.id] != nil)
    }

    @Test func removingTheMatchesOfOtherWalksKeepsOnlyTheGivenWalks() throws {
        let cache = try cache()
        cache.store(match(), for: key(0))
        cache.store(match(), for: key(60))

        cache.removeAll(except: [key(60)])

        #expect(cache.match(for: key(0)) == nil)
        #expect(cache.match(for: key(60)) != nil)
    }

    @Test func aNewMapReleaseStartsAnEmptyCacheAndRemovesTheOldOne() throws {
        let old = try cache(mapRelease: "2026-02")
        old.store(match(), for: key(0))

        let new = try cache(mapRelease: "2027-02")

        #expect(new.match(for: key(0)) == nil)
        #expect(!FileManager.default.fileExists(atPath: old.folder.path))
    }
}
