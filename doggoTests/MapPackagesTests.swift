//
//  MapPackagesTests.swift
//  doggoTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import CoreLocation
import Foundation
import Testing
@testable import doggo

/// The tests read the fixture package and changed copies of it, which each
/// test makes in a folder of its own.
struct MapPackagesTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let fixture: URL
    let everywhere = [FixturePackage.everywhere]

    init() throws {
        fixture = try FixturePackage.url()
    }

    func copy(_ name: String, changedBy sql: String? = nil) throws -> URL {
        try FixturePackage.copy(named: name, in: folder, changedBy: sql)
    }

    /// The fixture as two packages: Dietikon, and the other areas.
    func split() throws -> MapPackages {
        MapPackages(urls: [
            try copy("dietikon.sqlite", changedBy: """
                DELETE FROM segments WHERE area != 243; DELETE FROM areas WHERE bfs_number != 243;
                DELETE FROM streets WHERE area != 243;
                """),
            try copy("others.sqlite", changedBy: """
                DELETE FROM segments WHERE area = 243; DELETE FROM areas WHERE bfs_number = 243;
                DELETE FROM streets WHERE area = 243;
                """),
        ])
    }

    // MARK: Reading all packages at once

    @Test func theSegmentsComeFromAllPackagesAndEachSegmentOnce() throws {
        let all = try MapPackages(urls: [fixture]).segments(in: everywhere)

        let fromTwo = try split().segments(in: everywhere)
        let twice = try MapPackages(urls: [fixture, copy("copy.sqlite")]).segments(in: everywhere)

        #expect(Set(fromTwo.map(\.id)) == Set(all.map(\.id)))
        #expect(twice.count == all.count)
    }

    @Test func anAreaAndItsShapeAreFoundInEveryPackage() throws {
        let packages = try split()

        let shape = try #require(try packages.shape(of: 246))

        #expect(shape.segments.count == 139)
        #expect(try packages.boundary(of: 246)?.isEmpty == false)
        #expect(try packages.shape(of: 243)?.segments.count == 268)
        #expect(try packages.shape(of: 9999) == nil)
        #expect(Set(try packages.areas().map(\.id)) == [243, 246, 4040])
    }

    @Test func theAreasOfThePackagesHaveTheTotalsOfTheirSegments() throws {
        let areas = try MapPackages(urls: [fixture]).areas()

        let dietikon = try #require(areas.first { $0.id == 243 })
        #expect(dietikon.name == "Dietikon")
        #expect(dietikon.canton == "ZH")
        #expect(dietikon.segmentCount == 268)
        #expect(abs(dietikon.lengthMetres - 24_568.94) < 0.01)
        #expect(Set(areas.map(\.id)) == [243, 246, 4040])
    }

    @Test func theStreetsOfThePackagesHaveTheTotalsOfTheirSegments() throws {
        let packages = MapPackages(urls: [fixture])

        let streets = try packages.streets()
        let segments = try packages.segments(in: everywhere)

        // Industriestrasse runs from Spreitenbach into Dietikon, so it is a street in both.
        let industriestrasse = streets.filter { $0.name == "Industriestrasse" }
        #expect(Set(industriestrasse.map(\.id.area)) == [243, 4040])
        for street in streets {
            let ofStreet = segments.filter { $0.streetID == street.id }
            #expect(street.segmentCount == ofStreet.count)
            #expect(abs(street.lengthMetres - ofStreet.reduce(0) { $0 + $1.lengthMetres }) < 0.01)
        }
        #expect(segments.contains { $0.street == nil })
    }

    @Test func theShapeOfAnAreaHasItsBoundaryAndAllItsSegmentsForTheSmallMap() throws {
        let shape = try #require(try MapPackages(urls: [fixture]).shape(of: 243))

        #expect(shape.segments.count == 268)
        #expect(shape.segments.allSatisfy { $0.area == 243 })
        let boundary = shape.boundary.flatMap { $0 }
        #expect(!boundary.isEmpty)
        // Dietikon lies between 8.36° and 8.44° east and 47.37° and 47.43° north.
        #expect(boundary.allSatisfy {
            (8.36...8.44).contains($0.longitude) && (47.37...47.43).contains($0.latitude)
        })
    }

    @Test func thePackagesFindSegmentsByTheirFeatureIDs() throws {
        let packages = try split()
        let segments = try packages.segments(in: everywhere)
        let wanted = [
            try #require(segments.first { $0.area == 243 }),
            try #require(segments.first { $0.area == 246 }),
        ]

        let found = try packages.segments(withFIDs: Set(wanted.map(\.fid)))

        #expect(Set(found.map(\.id)) == Set(wanted.map(\.id)))
        #expect(try packages.segments(withFIDs: []).isEmpty)
    }

    // MARK: Engines

    @Test func anEngineForATrackGivesTheSameCollectionAsAnEngineWithAllSegments() throws {
        let packages = MapPackages(urls: [fixture])
        let all = CollectionEngine(segments: try packages.segments(in: everywhere))
        let longSegment = try #require(try packages.segments(in: everywhere)
            .first { $0.id == CollectionEngineTests.longSegmentID })
        let start = Date(timeIntervalSinceReferenceDate: 812_000_000)
        let walk = CollectionEngine.Walk(dogs: ["Bello"], track: syntheticTrack(along: longSegment, to: 0.6, startingAt: start))

        let forTrack = try packages.engine(covering: [walk.track])

        let collections = forTrack.rebuild(dogs: ["Bello"], walks: [walk])
        #expect(collections["Bello"]?.coveredParts.isEmpty == false)
        #expect(collections == all.rebuild(dogs: ["Bello"], walks: [walk]))
    }

    @Test func anEngineAroundAPointFindsTheSameNewSegmentsAsAnEngineWithAllSegments() throws {
        let packages = MapPackages(urls: [fixture])
        let all = CollectionEngine(segments: try packages.segments(in: everywhere))
        let point = CLLocationCoordinate2D(latitude: 47.4045, longitude: 8.4003)

        let around = try packages.engine(around: point, withinMetres: 1500)

        let near = around.newSegments(near: point, withinMetres: 500, for: ["Bello"], in: [:])
        #expect(!near.isEmpty)
        #expect(Set(near.map(\.id)) == Set(all.newSegments(near: point, withinMetres: 500, for: ["Bello"], in: [:]).map(\.id)))
    }

    // MARK: Failures

    @Test func aPackageThatCannotOpenMakesEveryReadFailUntilItIsFixed() async throws {
        let broken = folder.appending(path: "zh.sqlite")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not a map package".utf8).write(to: broken)
        let packages = MapPackages(urls: [fixture, broken])

        #expect(throws: (any Error).self) { try packages.segments(in: everywhere) }
        #expect(throws: (any Error).self) { try packages.areas() }
        #expect(throws: (any Error).self) { try packages.shape(of: 243) }
        #expect(throws: (any Error).self) { try packages.identity() }
        await #expect(throws: (any Error).self) { try await packages.check() }

        try FileManager.default.removeItem(at: broken)
        try FileManager.default.copyItem(at: fixture, to: broken)

        #expect(try !packages.segments(in: everywhere).isEmpty)
    }

    @Test func aBrokenSegmentMakesTheSegmentsFailInsteadOfGivingNone() throws {
        let broken = try copy("broken.sqlite", changedBy: "UPDATE segments SET geometry = x'00'")

        #expect(throws: MapPackage.Error.self) { try MapPackages(urls: [broken]).segments(in: everywhere) }
    }

    @Test func aPackageOfAnUnknownFormatVersionCannotOpen() throws {
        let newer = try copy("newer.sqlite", changedBy: "UPDATE meta SET value = '99' WHERE key = 'format_version'")

        #expect(throws: MapPackage.Error.self) { try MapPackages(urls: [newer]).areas() }
    }

    @Test func packagesOfDifferentMapReleasesCannotBeReadTogether() throws {
        let other = try copy("other.sqlite", changedBy: "UPDATE meta SET value = 'other' WHERE key = 'map_release'")

        #expect(throws: MapPackages.Error.self) { try MapPackages(urls: [fixture, other]).segments(in: everywhere) }
        #expect(try !MapPackages(urls: [other]).segments(in: everywhere).isEmpty)
    }

    // MARK: Identity

    @Test func theIdentityChangesWithANewARenamedOrAChangedPackage() throws {
        let identity = try MapPackages(urls: [fixture]).identity()
        let other = try copy("other.sqlite")
        let renamed = try copy("renamed.sqlite")
        let newRelease = try FixturePackage.copy(
            named: "fixture.sqlite", in: folder.appending(path: "new"),
            changedBy: "UPDATE meta SET value = 'next' WHERE key = 'map_release'")

        #expect(try MapPackages(urls: [fixture, other]).identity() != identity)
        #expect(try MapPackages(urls: [renamed]).identity() != identity)
        #expect(try MapPackages(urls: [newRelease]).identity() != identity)
        #expect(try MapPackages(urls: [fixture, other]).identity() == MapPackages(urls: [other, fixture]).identity())
    }

    // MARK: Tiles

    @Test func theTilesOfTheFixtureAndOfTheBundledPackagesAreTheTilesThatTheMapDraws() async throws {
        #expect(!MapPackages.bundled.urls.isEmpty)

        try await MapPackages(urls: [fixture]).check()
        try await MapPackages.bundled.check()
    }

    @Test(arguments: [
        #"replace(value, '"id":"segments"', '"id":"lines"')"#,
        #"replace(value, '"minzoom":12', '"minzoom":10')"#,
        #"replace(value, '"area":"Number"', '"bfs":"Number"')"#,
    ])
    func tilesWithAnotherLayerZoomOrPropertyFailTheCheck(change: String) async throws {
        let changed = try copy("changed.sqlite", changedBy: "UPDATE metadata SET value = \(change) WHERE name = 'json'")

        await #expect(throws: MapPackages.Error.self) { try await MapPackages(urls: [changed]).check() }
    }

    @Test func eachPackageIsATileSourceForTheMap() throws {
        let sources = try split().tileSources

        #expect(sources.map(\.name) == ["dietikon", "others"])
        #expect(sources.first?.url.absoluteString == "mbtiles://" + folder.appending(path: "dietikon.sqlite").path)
    }
}
