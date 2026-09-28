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
    nonisolated struct ID: Hashable, Sendable {
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

    /// The box grown by the given fraction of its size on each side.
    func expanded(by fraction: Double) -> CoordinateBox {
        let width = (maxLongitude - minLongitude) * fraction
        let height = (maxLatitude - minLatitude) * fraction
        return CoordinateBox(
            minLongitude: minLongitude - width, maxLongitude: maxLongitude + width,
            minLatitude: minLatitude - height, maxLatitude: maxLatitude + height)
    }
}

/// Reads one map package: the SQLite file that the map build writes.
/// See `mapbuild/PACKAGE_FORMAT.md` for the format.
nonisolated final class MapPackage {
    enum Error: Swift.Error {
        case cannotOpen(String)
        case query(String)
        case unsupportedFormatVersion(String?)
        case invalidGeometry(segment: String)
        case invalidBoundary(area: Int)
    }

    static let supportedFormatVersion = "3"

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

    /// The bundled map packages, one for each canton.
    static func bundled() throws -> [MapPackage] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "sqlite", subdirectory: nil) ?? []
        return try urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.map(MapPackage.init)
    }

    /// The segments of all packages whose bounding box overlaps one of the
    /// boxes, each segment once. A package that cannot be read gives none.
    static func segments(in boxes: [CoordinateBox], of packages: [MapPackage]) -> [Segment] {
        var segments: [Segment.ID: Segment] = [:]
        for package in packages {
            for segment in (try? package.segments(in: boxes)) ?? [] {
                segments[segment.id] = segment
            }
        }
        return Array(segments.values)
    }

    /// The segments whose bounding box overlaps the given box, from the spatial index.
    func segments(in box: CoordinateBox) throws -> [Segment] {
        try segments(in: [box])
    }

    /// The segments whose bounding box overlaps one of the boxes, from the
    /// spatial index. A segment in several boxes comes once for each box.
    private func segments(in boxes: [CoordinateBox]) throws -> [Segment] {
        let statement = try Self.prepare(
            """
            SELECT s.id, s.area, s.way_class, s.street, s.length_m, s.geometry
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

    /// The boundary and the segments of an area, or nil if the package does
    /// not hold the area.
    func shape(of area: Int) throws -> AreaShape? {
        let boundaryStatement = try Self.prepare("SELECT boundary FROM areas WHERE bfs_number = ?", in: database)
        defer { sqlite3_finalize(boundaryStatement) }
        sqlite3_bind_int64(boundaryStatement, 1, Int64(area))
        guard sqlite3_step(boundaryStatement) == SQLITE_ROW else { return nil }
        let bytes = sqlite3_column_blob(boundaryStatement, 0)
        let count = Int(sqlite3_column_bytes(boundaryStatement, 0))
        guard let bytes,
              let boundary = Self.rings(fromMultiPolygonWKB: UnsafeRawBufferPointer(start: bytes, count: count)),
              let box = Self.box(of: boundary.flatMap { $0 })
        else { throw Error.invalidBoundary(area: area) }

        // The segments table has no index on the area, so the spatial index
        // finds the segments in the box of the boundary first.
        let statement = try Self.prepare(
            """
            SELECT s.id, s.area, s.way_class, s.street, s.length_m, s.geometry
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
