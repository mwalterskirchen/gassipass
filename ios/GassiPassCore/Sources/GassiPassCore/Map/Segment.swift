//
//  Segment.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import Foundation

/// A segment as the map package stores it.
public nonisolated struct Segment: Identifiable, Sendable {
    public let id: String
    /// The number of the segment in the map release, which is also its
    /// feature ID in the map tiles. It is unique across all packages of a
    /// map release, but a new map release can change it.
    public let fid: Int
    /// The BFS number of the area that the segment lies in.
    public let area: Int
    /// The swissTLM3D way class (`OBJEKTART`), for example "2m Weg".
    public let wayClass: String
    /// The official street name, or nil if the segment has no name.
    public let street: String?
    public let lengthMetres: Double
    public let coordinates: [CLLocationCoordinate2D]

    /// The street that the segment belongs to, or nil if it has no name.
    public var streetID: Street.ID? {
        street.map { Street.ID(area: area, name: $0) }
    }

    public init(
        id: String,
        fid: Int,
        area: Int,
        wayClass: String,
        street: String?,
        lengthMetres: Double,
        coordinates: [CLLocationCoordinate2D]
    ) {
        self.id = id
        self.fid = fid
        self.area = area
        self.wayClass = wayClass
        self.street = street
        self.lengthMetres = lengthMetres
        self.coordinates = coordinates
    }
}

/// An area (a Gemeinde) as the map package stores it, with the totals of
/// its segments.
public nonisolated struct Area: Identifiable, Sendable {
    /// The BFS number.
    public let id: Int
    public let name: String
    /// The two-letter abbreviation of the canton, for example "ZH".
    public let canton: String
    public let segmentCount: Int
    public let lengthMetres: Double

    public init(id: Int, name: String, canton: String, segmentCount: Int, lengthMetres: Double) {
        self.id = id
        self.name = name
        self.canton = canton
        self.segmentCount = segmentCount
        self.lengthMetres = lengthMetres
    }
}

/// A street: all segments with the same official name in the same area,
/// with the totals of its segments. The same name in another area is
/// another street.
public nonisolated struct Street: Identifiable, Sendable {
    public nonisolated struct ID: Codable, Hashable, Sendable {
        /// The BFS number of the area.
        public let area: Int
        public let name: String

        public init(area: Int, name: String) {
            self.area = area
            self.name = name
        }
    }

    public let id: ID
    public let segmentCount: Int
    public let lengthMetres: Double

    public var name: String { id.name }

    public init(id: ID, segmentCount: Int, lengthMetres: Double) {
        self.id = id
        self.segmentCount = segmentCount
        self.lengthMetres = lengthMetres
    }
}

/// The boundary of an area and all its segments, for the small map of the
/// area.
public nonisolated struct AreaShape: Sendable {
    /// The rings of the boundary polygons, both outer rings and holes.
    public let boundary: [[CLLocationCoordinate2D]]
    public let segments: [Segment]

    public init(boundary: [[CLLocationCoordinate2D]], segments: [Segment]) {
        self.boundary = boundary
        self.segments = segments
    }
}

/// A box of longitudes and latitudes in degrees.
public nonisolated struct CoordinateBox: Sendable {
    public var minLongitude: Double
    public var maxLongitude: Double
    public var minLatitude: Double
    public var maxLatitude: Double

    public func contains(_ other: CoordinateBox) -> Bool {
        minLongitude <= other.minLongitude && other.maxLongitude <= maxLongitude
            && minLatitude <= other.minLatitude && other.maxLatitude <= maxLatitude
    }

    public init(minLongitude: Double, maxLongitude: Double, minLatitude: Double, maxLatitude: Double) {
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
    }
}
