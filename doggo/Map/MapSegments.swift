//
//  MapSegments.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import MapLibre

/// Reads the segments of the bundled map packages for `SegmentMapView` and
/// builds the features of the map from them, off the main thread. It opens
/// its own packages once, like the rebuild of the collections, because the
/// others are read at the same time.
actor MapSegments {
    static let shared = MapSegments()

    /// The packages, or the error that stopped them from opening, after the first use.
    private var packages: Result<[MapPackage], any Error>?

    /// Opens the packages, unless they are open already.
    func open() throws {
        _ = try openPackages()
    }

    /// The segments of all packages near the box. A package that cannot be
    /// read gives none.
    func segments(in box: CoordinateBox) -> [Segment] {
        guard let packages = try? openPackages() else { return [] }
        return packages.flatMap { (try? $0.segments(in: box)) ?? [] }
    }

    /// The features of the segments for the map. Each feature has the ID of
    /// its segment, whether the segment is collected, and its area.
    func features(of segments: [Segment], collected: Set<Segment.ID>) -> sending MLNShapeCollectionFeature {
        MLNShapeCollectionFeature(shapes: segments.map { segment in
            var coordinates = segment.coordinates
            let feature = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
            feature.identifier = segment.id
            feature.attributes = ["collected": collected.contains(segment.id), "area": segment.area]
            return feature
        })
    }

    private func openPackages() throws -> [MapPackage] {
        if packages == nil {
            packages = Result { try MapPackage.bundled() }
        }
        return try packages!.get()
    }
}
