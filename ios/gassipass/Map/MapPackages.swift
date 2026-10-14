//
//  MapPackages.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import CoreLocation
import Foundation

/// The map packages on the phone, one for each canton, all of the same map
/// release. See `mapbuild/PACKAGE_FORMAT.md` for the format.
///
/// It answers from all packages at once, so that a caller never needs to
/// know which package holds a segment or an area. Each read opens its own
/// connections to the packages and closes them again. So any actor can read
/// at any time, and nothing remembers a failure: the next read tries again.
/// A read throws if one package cannot open or read, because a missing
/// package would look like a place with no segments.
nonisolated struct MapPackages: Sendable {
    enum Error: Swift.Error {
        /// The packages have different map releases. The feature IDs of the
        /// segments are unique only within one map release.
        case mixedMapReleases([String])
        /// The tiles of the package are not the tiles that the map draws.
        case unexpectedTiles(package: String)
    }

    /// A package as a source of tiles for the map. The tiles have one layer,
    /// `tileLayer`. The feature ID of a line in it is the `fid` of its
    /// segment, and its property `areaProperty` is the BFS number of the
    /// area of the segment.
    struct TileSource: Sendable {
        /// The name of the package, for example "zh".
        let name: String
        /// The URL of the package for MapLibre.
        let url: URL
    }

    /// The layer of the segments in the tiles.
    static let tileLayer = "segments"
    /// The zoom levels of the tiles. The map zooms the tiles of the highest
    /// level further in, and shows no segments below the lowest level.
    static let tileZoomLevels = 12...14
    /// The property of a line in the tiles that holds the BFS number of the
    /// area of its segment.
    static let areaProperty = "area"

    /// The packages that the app bundles.
    static let bundled = MapPackages(
        urls: (Bundle.main.urls(forResourcesWithExtension: "sqlite", subdirectory: nil) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent })

    let urls: [URL]

    /// The name of the packages and their map release, for the folders of
    /// caches. A new package, a renamed package or a new map release gives
    /// another identity. The order of the packages does not matter.
    func identity() throws -> String {
        try zip(urls, open()).map { "\($0.lastPathComponent) \($1.mapRelease)" }.sorted().joined(separator: " + ")
    }

    /// Checks that every package opens, that the packages have one map
    /// release, and that their tiles are the tiles that the map draws.
    @concurrent func check() async throws {
        for (url, package) in try zip(urls, open()) {
            guard try Self.hasExpectedTiles(package) else {
                throw Error.unexpectedTiles(package: url.lastPathComponent)
            }
        }
    }

    /// The segments whose bounding box overlaps one of the boxes, each
    /// segment once.
    func segments(in boxes: [CoordinateBox]) throws -> [Segment] {
        var segments: [Segment.ID: Segment] = [:]
        for package in try open() {
            for segment in try package.segments(in: boxes) {
                segments[segment.id] = segment
            }
        }
        return Array(segments.values)
    }

    /// The segments with the given feature IDs.
    func segments(withFIDs fids: Set<Int>) throws -> [Segment] {
        try open().flatMap { try $0.segments(withFIDs: fids) }
    }

    /// All areas, with the number and total length of their segments.
    func areas() throws -> [Area] {
        try open().flatMap { try $0.areas() }
    }

    /// All streets, with the number and total length of their segments.
    func streets() throws -> [Street] {
        try open().flatMap { try $0.streets() }
    }

    /// The rings of the boundary of an area, or nil if no package holds the area.
    func boundary(of area: Int) throws -> [[CLLocationCoordinate2D]]? {
        for package in try open() {
            if let boundary = try package.boundary(of: area) {
                return boundary
            }
        }
        return nil
    }

    /// The boundary and the segments of an area, or nil if no package holds the area.
    func shape(of area: Int) throws -> AreaShape? {
        for package in try open() {
            if let shape = try package.shape(of: area) {
                return shape
            }
        }
        return nil
    }

    /// The packages as sources of tiles for the map.
    var tileSources: [TileSource] {
        urls.compactMap { url in
            URL(string: "mbtiles://\(url.path)").map {
                TileSource(name: url.deletingPathExtension().lastPathComponent, url: $0)
            }
        }
    }

    /// Opens every package, and checks that they have one map release.
    private func open() throws -> [MapPackage] {
        let packages = try urls.map(MapPackage.init(url:))
        let releases = Set(packages.map(\.mapRelease))
        guard releases.count <= 1 else { throw Error.mixedMapReleases(releases.sorted()) }
        return packages
    }

    /// Whether the tiles of the package have the layer, the zoom levels and
    /// the property that the map uses.
    private static func hasExpectedTiles(_ package: MapPackage) throws -> Bool {
        guard let json = try package.tileMetadata(),
              let metadata = try? JSONDecoder().decode(TileMetadata.self, from: Data(json.utf8))
        else { return false }
        return metadata.vectorLayers.contains { layer in
            layer.id == tileLayer && layer.minzoom...layer.maxzoom == tileZoomLevels
                && layer.fields[areaProperty] != nil
        }
    }

    /// The part of the MBTiles metadata that describes the layers of the tiles.
    private struct TileMetadata: Decodable {
        struct Layer: Decodable {
            let id: String
            let minzoom: Int
            let maxzoom: Int
            let fields: [String: String]
        }

        let vectorLayers: [Layer]

        enum CodingKeys: String, CodingKey {
            case vectorLayers = "vector_layers"
        }
    }
}
