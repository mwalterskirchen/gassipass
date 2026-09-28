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
