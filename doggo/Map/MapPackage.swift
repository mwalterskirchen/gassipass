//
//  MapPackage.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import Foundation
import SQLite3

/// A segment as the map package stores it.
nonisolated struct Segment: Identifiable, Sendable {
    let id: String
    /// The BFS number of the area that the segment lies in.
    let area: Int
    /// The swissTLM3D way class (`OBJEKTART`), for example "2m Weg".
    let wayClass: String
    let lengthMetres: Double
    let coordinates: [CLLocationCoordinate2D]
}

/// Reads one map package: the SQLite file that the map build writes.
/// See `mapbuild/PACKAGE_FORMAT.md` for the format.
nonisolated final class MapPackage {
    enum Error: Swift.Error {
        case cannotOpen(String)
        case query(String)
        case unsupportedFormatVersion(String?)
        case invalidGeometry(segment: String)
    }

    static let supportedFormatVersion = "1"

    private let database: OpaquePointer

    let mapRelease: String

    init(url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle
        else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? url.path
            sqlite3_close(handle)
            throw Error.cannotOpen(message)
        }
        database = handle

        let version = try Self.metaValue("format_version", in: handle)
        guard version == Self.supportedFormatVersion else {
            sqlite3_close(handle)
            throw Error.unsupportedFormatVersion(version)
        }
        mapRelease = try Self.metaValue("map_release", in: handle) ?? ""
    }

    deinit {
        sqlite3_close(database)
    }

    func segments() throws -> [Segment] {
        let statement = try Self.prepare(
            "SELECT id, area, way_class, length_m, geometry FROM segments", in: database)
        defer { sqlite3_finalize(statement) }

        var segments: [Segment] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let bytes = sqlite3_column_blob(statement, 4)
            let count = Int(sqlite3_column_bytes(statement, 4))
            guard let bytes,
                  let coordinates = Self.lineString(fromWKB: UnsafeRawBufferPointer(start: bytes, count: count))
            else { throw Error.invalidGeometry(segment: id) }
            segments.append(Segment(
                id: id,
                area: Int(sqlite3_column_int64(statement, 1)),
                wayClass: String(cString: sqlite3_column_text(statement, 2)),
                lengthMetres: sqlite3_column_double(statement, 3),
                coordinates: coordinates))
        }
        return segments
    }

    private static func metaValue(_ key: String, in database: OpaquePointer) throws -> String? {
        let statement = try prepare("SELECT value FROM meta WHERE key = ?", in: database)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return String(cString: sqlite3_column_text(statement, 0))
    }

    private static func prepare(_ sql: String, in database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Error.query(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    /// Parses a little-endian WKB LineString with longitude and latitude.
    private static func lineString(fromWKB wkb: UnsafeRawBufferPointer) -> [CLLocationCoordinate2D]? {
        let headerSize = 1 + 4 + 4
        guard wkb.count >= headerSize,
              wkb.load(as: UInt8.self) == 1,
              UInt32(littleEndian: wkb.loadUnaligned(fromByteOffset: 1, as: UInt32.self)) == 2
        else { return nil }
        let pointCount = Int(UInt32(littleEndian: wkb.loadUnaligned(fromByteOffset: 5, as: UInt32.self)))
        guard wkb.count == headerSize + pointCount * 16 else { return nil }
        return (0..<pointCount).map { index in
            let offset = headerSize + index * 16
            let longitude = wkb.loadUnaligned(fromByteOffset: offset, as: Double.self)
            let latitude = wkb.loadUnaligned(fromByteOffset: offset + 8, as: Double.self)
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
}

nonisolated private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
