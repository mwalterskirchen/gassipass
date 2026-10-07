//
//  MapPackage.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import Foundation
import SQLite3

/// A segment as the map package stores it.
nonisolated struct Segment: Identifiable, Sendable {
    let id: String
    /// The number of the segment in the map release, which is also its
    /// feature ID in the map tiles. It is unique across all packages of a
    /// map release, but a new map release can change it.
    let fid: Int
    /// The BFS number of the area that the segment lies in.
    let area: Int
    /// The swissTLM3D way class (`OBJEKTART`), for example "2m Weg".
    let wayClass: String
    /// The official street name, or nil if the segment has no name.
    let street: String?
    let lengthMetres: Double
    let coordinates: [CLLocationCoordinate2D]

    /// The street that the segment belongs to, or nil if it has no name.
    var streetID: Street.ID? {
        street.map { Street.ID(area: area, name: $0) }
    }
}

/// An area (a Gemeinde) as the map package stores it, with the totals of
/// its segments.
nonisolated struct Area: Identifiable, Sendable {
    /// The BFS number.
    let id: Int
    let name: String
    /// The two-letter abbreviation of the canton, for example "ZH".
    let canton: String
    let segmentCount: Int
    let lengthMetres: Double
}

/// A street: all segments with the same official name in the same area,
/// with the totals of its segments. The same name in another area is
/// another street.
nonisolated struct Street: Identifiable, Sendable {
    nonisolated struct ID: Codable, Hashable, Sendable {
        /// The BFS number of the area.
        let area: Int
        let name: String
    }

    let id: ID
    let segmentCount: Int
    let lengthMetres: Double

    var name: String { id.name }
}

/// The boundary of an area and all its segments, for the small map of the
/// area.
nonisolated struct AreaShape: Sendable {
    /// The rings of the boundary polygons, both outer rings and holes.
    let boundary: [[CLLocationCoordinate2D]]
    let segments: [Segment]
}

/// A box of longitudes and latitudes in degrees.
nonisolated struct CoordinateBox: Sendable {
    var minLongitude: Double
    var maxLongitude: Double
    var minLatitude: Double
    var maxLatitude: Double

    func contains(_ other: CoordinateBox) -> Bool {
        minLongitude <= other.minLongitude && other.maxLongitude <= maxLongitude
            && minLatitude <= other.minLatitude && other.maxLatitude <= maxLatitude
    }
}

/// Reads one map package: the SQLite file that the map build writes.
/// See `mapbuild/PACKAGE_FORMAT.md` for the format. Only `MapPackages`
/// uses it, which reads all packages at once.
nonisolated final class MapPackage {
    enum Error: Swift.Error {
        case cannotOpen(String)
        case query(String)
        case unsupportedFormatVersion(String?)
        case invalidGeometry(segment: String)
        case invalidBoundary(area: Int)
    }

    static let supportedFormatVersion = "4"

    /// Larger than any package, so that the whole file is mapped.
    private static let mmapSize = 1 << 30

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
        // The package never changes, so SQLite can read it straight from
        // memory-mapped pages instead of copying them into its cache.
        sqlite3_exec(handle, "PRAGMA mmap_size = \(Self.mmapSize)", nil, nil, nil)

        do {
            let version = try Self.metaValue("format_version", in: handle)
            guard version == Self.supportedFormatVersion else { throw Error.unsupportedFormatVersion(version) }
            mapRelease = try Self.metaValue("map_release", in: handle) ?? ""
        } catch {
            // The object does not exist, so its deinit does not close the database.
            sqlite3_close(handle)
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    /// The segments whose bounding box overlaps one of the boxes, from the
    /// spatial index. A segment in several boxes comes once for each box.
    func segments(in boxes: [CoordinateBox]) throws -> [Segment] {
        let statement = try Self.prepare(
            """
            SELECT s.id, s.area, s.way_class, s.street, s.length_m, s.geometry, s.fid
            FROM segments_index i JOIN segments s ON s.fid = i.fid
            WHERE i.max_lon >= ? AND i.min_lon <= ? AND i.max_lat >= ? AND i.min_lat <= ?
            """, in: database)
        defer { sqlite3_finalize(statement) }
        var segments: [Segment] = []
        for box in boxes {
            sqlite3_reset(statement)
            sqlite3_bind_double(statement, 1, box.minLongitude)
            sqlite3_bind_double(statement, 2, box.maxLongitude)
            sqlite3_bind_double(statement, 3, box.minLatitude)
            sqlite3_bind_double(statement, 4, box.maxLatitude)
            segments += try Self.readSegments(statement)
        }
        return segments
    }

    /// All areas of the package, with the number and total length of their
    /// segments, which the map build stores.
    func areas() throws -> [Area] {
        let statement = try Self.prepare(
            "SELECT bfs_number, name, canton, segment_count, length_m FROM areas", in: database)
        defer { sqlite3_finalize(statement) }
        var areas: [Area] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            areas.append(Area(
                id: Int(sqlite3_column_int64(statement, 0)),
                name: String(cString: sqlite3_column_text(statement, 1)),
                canton: String(cString: sqlite3_column_text(statement, 2)),
                segmentCount: Int(sqlite3_column_int64(statement, 3)),
                lengthMetres: sqlite3_column_double(statement, 4)))
        }
        return areas
    }

    /// All streets of the package, with the number and total length of their
    /// segments, which the map build stores.
    func streets() throws -> [Street] {
        let statement = try Self.prepare(
            "SELECT area, name, segment_count, length_m FROM streets", in: database)
        defer { sqlite3_finalize(statement) }
        var streets: [Street] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            streets.append(Street(
                id: Street.ID(
                    area: Int(sqlite3_column_int64(statement, 0)),
                    name: String(cString: sqlite3_column_text(statement, 1))),
                segmentCount: Int(sqlite3_column_int64(statement, 2)),
                lengthMetres: sqlite3_column_double(statement, 3)))
        }
        return streets
    }

    /// The MBTiles metadata of the tiles as JSON, which describes their
    /// layers, or nil if the package has none.
    func tileMetadata() throws -> String? {
        let statement = try Self.prepare("SELECT value FROM metadata WHERE name = 'json'", in: database)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return String(cString: sqlite3_column_text(statement, 0))
    }

    /// The rings of the boundary of an area, or nil if the package does not
    /// hold the area.
    func boundary(of area: Int) throws -> [[CLLocationCoordinate2D]]? {
        let statement = try Self.prepare("SELECT boundary FROM areas WHERE bfs_number = ?", in: database)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(area))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let bytes = sqlite3_column_blob(statement, 0)
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard let bytes,
              let boundary = Self.rings(fromMultiPolygonWKB: UnsafeRawBufferPointer(start: bytes, count: count))
        else { throw Error.invalidBoundary(area: area) }
        return boundary
    }

    /// The segments with the given fids that the package holds.
    func segments(withFIDs fids: Set<Int>) throws -> [Segment] {
        let statement = try Self.prepare(
            """
            SELECT id, area, way_class, street, length_m, geometry, fid
            FROM segments WHERE fid IN (SELECT value FROM json_each(?))
            """, in: database)
        defer { sqlite3_finalize(statement) }
        let list = "[" + fids.map(String.init).joined(separator: ",") + "]"
        sqlite3_bind_text(statement, 1, list, -1, SQLITE_TRANSIENT)
        return try Self.readSegments(statement)
    }

    /// The boundary and the segments of an area, or nil if the package does
    /// not hold the area.
    func shape(of area: Int) throws -> AreaShape? {
        guard let boundary = try boundary(of: area) else { return nil }
        guard let box = Self.box(of: boundary.flatMap { $0 }) else { throw Error.invalidBoundary(area: area) }

        // The segments table has no index on the area, so the spatial index
        // finds the segments in the box of the boundary first.
        let statement = try Self.prepare(
            """
            SELECT s.id, s.area, s.way_class, s.street, s.length_m, s.geometry, s.fid
            FROM segments_index i JOIN segments s ON s.fid = i.fid
            WHERE i.max_lon >= ? AND i.min_lon <= ? AND i.max_lat >= ? AND i.min_lat <= ? AND s.area = ?
            """, in: database)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, box.minLongitude)
        sqlite3_bind_double(statement, 2, box.maxLongitude)
        sqlite3_bind_double(statement, 3, box.minLatitude)
        sqlite3_bind_double(statement, 4, box.maxLatitude)
        sqlite3_bind_int64(statement, 5, Int64(area))
        return AreaShape(boundary: boundary, segments: try Self.readSegments(statement))
    }

    private static func box(of coordinates: [CLLocationCoordinate2D]) -> CoordinateBox? {
        guard let first = coordinates.first else { return nil }
        var box = CoordinateBox(minLongitude: first.longitude, maxLongitude: first.longitude,
                                minLatitude: first.latitude, maxLatitude: first.latitude)
        for coordinate in coordinates {
            box.minLongitude = min(box.minLongitude, coordinate.longitude)
            box.maxLongitude = max(box.maxLongitude, coordinate.longitude)
            box.minLatitude = min(box.minLatitude, coordinate.latitude)
            box.maxLatitude = max(box.maxLatitude, coordinate.latitude)
        }
        return box
    }

    private static func readSegments(_ statement: OpaquePointer) throws -> [Segment] {
        var segments: [Segment] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let bytes = sqlite3_column_blob(statement, 5)
            let count = Int(sqlite3_column_bytes(statement, 5))
            guard let bytes,
                  let coordinates = lineString(fromWKB: UnsafeRawBufferPointer(start: bytes, count: count))
            else { throw Error.invalidGeometry(segment: id) }
            segments.append(Segment(
                id: id,
                fid: Int(sqlite3_column_int64(statement, 6)),
                area: Int(sqlite3_column_int64(statement, 1)),
                wayClass: String(cString: sqlite3_column_text(statement, 2)),
                street: sqlite3_column_text(statement, 3).map { String(cString: $0) },
                lengthMetres: sqlite3_column_double(statement, 4),
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

    /// Parses a little-endian WKB MultiPolygon with longitude and latitude
    /// into the rings of all its polygons.
    private static func rings(fromMultiPolygonWKB wkb: UnsafeRawBufferPointer) -> [[CLLocationCoordinate2D]]? {
        var offset = 0
        func readHeader(type: UInt32) -> Bool {
            guard let order = readByte(), order == 1, let found = readCount() else { return false }
            return UInt32(found) == type
        }
        func readByte() -> UInt8? {
            guard offset + 1 <= wkb.count else { return nil }
            defer { offset += 1 }
            return wkb.load(fromByteOffset: offset, as: UInt8.self)
        }
        func readCount() -> Int? {
            guard offset + 4 <= wkb.count else { return nil }
            defer { offset += 4 }
            return Int(UInt32(littleEndian: wkb.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
        }
        guard readHeader(type: 6), let polygonCount = readCount() else { return nil }
        var rings: [[CLLocationCoordinate2D]] = []
        for _ in 0..<polygonCount {
            guard readHeader(type: 3), let ringCount = readCount() else { return nil }
            for _ in 0..<ringCount {
                guard let pointCount = readCount(), offset + pointCount * 16 <= wkb.count else { return nil }
                rings.append((0..<pointCount).map { index in
                    let longitude = wkb.loadUnaligned(fromByteOffset: offset + index * 16, as: Double.self)
                    let latitude = wkb.loadUnaligned(fromByteOffset: offset + index * 16 + 8, as: Double.self)
                    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                })
                offset += pointCount * 16
            }
        }
        return offset == wkb.count ? rings : nil
    }
}

nonisolated private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
