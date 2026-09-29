//
//  FixturePackage.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import SQLite3
import Testing
@testable import gassipass

/// The map package that the map build made from the Dietikon fixture
/// (`mapbuild/tests/fixtures`), with Dietikon, Oetwil an der Limmat and
/// Spreitenbach. `make test-package` in `mapbuild/` writes it again.
enum FixturePackage {
    static let everywhere = CoordinateBox(minLongitude: -180, maxLongitude: 180, minLatitude: -90, maxLatitude: 90)

    static func url() throws -> URL {
        try #require(Bundle(for: Marker.self).url(forResource: "fixture", withExtension: "sqlite"))
    }

    /// All segments of the fixture.
    static func segments() throws -> [Segment] {
        try MapPackages(urls: [url()]).segments(in: [everywhere])
    }

    /// A copy of the fixture with the name in the folder, changed by the SQL.
    static func copy(named name: String, in folder: URL, changedBy sql: String? = nil) throws -> URL {
        let copy = folder.appending(path: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url(), to: copy)
        if let sql {
            var database: OpaquePointer?
            defer { sqlite3_close(database) }
            try #require(sqlite3_open(copy.path, &database) == SQLITE_OK)
            try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        }
        return copy
    }

    private final class Marker {}
}
