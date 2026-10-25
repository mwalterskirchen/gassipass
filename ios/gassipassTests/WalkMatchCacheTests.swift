//
//  WalkMatchCacheTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import Testing
@testable import gassipass

struct WalkMatchCacheTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let segment = straightSegment(id: "long", area: 9001, startLatitude: 47.400, startLongitude: 8.400, eastMetres: 1000)
    let start = Date(timeIntervalSinceReferenceDate: 812_000_000)

    func key(_ minutes: Double) -> WalkMatchCache.Key {
        WalkMatchCache.Key(startedAt: start.addingTimeInterval(minutes * 60),
                           endedAt: start.addingTimeInterval(minutes * 60 + 900), distanceMetres: 1000)
    }

    func cache(packages identity: String) throws -> WalkMatchCache {
        try #require(WalkMatchCache.forPackages(identity, in: root))
    }

    func match() -> WalkMatch {
        CollectionEngine(segments: [segment]).match(syntheticTrack(along: segment, startingAt: start))
    }

    @Test func newPackagesStartAnEmptyCacheAndRemoveTheOldOne() throws {
        let old = try cache(packages: "zh.sqlite 2026-02")
        old.store(match(), for: key(0))

        let new = try cache(packages: "zh.sqlite 2027-02")

        #expect(new.match(for: key(0)) == nil)
        #expect(!FileManager.default.fileExists(atPath: old.folder.path))
    }
}

extension WalkMatchCacheTests {
    /// A match along two segments, one of them on a street.
    func matchWithAStreet() -> WalkMatch {
        let street = straightSegment(
            id: "street", area: 9001, street: "Bahnhofstrasse", startLatitude: 47.401, startLongitude: 8.400,
            eastMetres: 500)
        let engine = CollectionEngine(segments: [segment, street])
        let along = syntheticTrack(along: segment, startingAt: start)
        let then = syntheticTrack(along: street, startingAt: along.points.last!.timestamp + 60)
        return engine.match(Track(points: along.points + then.points))
    }

    @Test func aStoredMatchReadsBackTheSame() throws {
        let cache = try cache(packages: "zh.sqlite 2026-02")
        let match = matchWithAStreet()
        #expect(match.entries.count == 2)

        cache.store(match, for: key(0))

        #expect(cache.match(for: key(0)) == match)
    }

    @Test func aStoredHistoryReadsBackTheSame() throws {
        let cache = try cache(packages: "zh.sqlite 2026-02")
        let bello = UUID(), luna = UUID()
        var history = CollectionHistory()
        history.keep(dogs: [bello, luna], walks: [key(0): [bello, luna], key(60): [bello]])
        history.add(matchWithAStreet(), of: key(0), for: [bello, luna])
        history.add(WalkMatch(), of: key(60), for: [bello])

        cache.store(history)

        #expect(cache.history() == history)
        #expect(cache.history()?.walks[key(60)]?.coversSegments == false)
    }

    @Test func aDamagedFileReadsAsNoMatchAndNoHistory() throws {
        let cache = try cache(packages: "zh.sqlite 2026-02")
        cache.store(match(), for: key(0))
        var history = CollectionHistory()
        history.keep(dogs: [UUID()], walks: [:])
        cache.store(history)

        for file in try FileManager.default.contentsOfDirectory(at: cache.folder, includingPropertiesForKeys: nil) {
            let data = try Data(contentsOf: file)
            try data.prefix(data.count - 3).write(to: file)
        }

        #expect(cache.match(for: key(0)) == nil)
        #expect(cache.history() == nil)
    }

    @Test func removingTheMatchesOfOtherWalksKeepsTheHistory() throws {
        let cache = try cache(packages: "zh.sqlite 2026-02")
        cache.store(match(), for: key(0))
        cache.store(CollectionHistory())

        cache.removeAll(except: [])

        #expect(cache.match(for: key(0)) == nil)
        #expect(cache.history() == CollectionHistory())
    }
}
