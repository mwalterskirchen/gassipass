//
//  MapSegments.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import MapLibre

/// Reads the segments of the bundled map packages for `SegmentMapView` and
/// builds the features of the map from them, off the main thread. It opens
/// its own packages once, because the rebuild of the collections and the
/// small area maps read their own packages at the same time.
actor MapSegments {
    /// The one reader of all map views, so that the packages open only once.
    static let shared = MapSegments()

    /// The packages, or the error that stopped them from opening, after the first use.
    private var packages: Result<[MapPackage], any Error>?

    /// Opens the packages, unless they are open already.
    func open() throws {
        _ = try openPackages()
    }

    /// The segments of all packages near the box. A package that cannot be
    /// read gives none. A cancelled task gets none, because a newer load
    /// replaces it, and several loads can wait for the actor after fast pans.
    func segments(in box: CoordinateBox) -> [Segment] {
        guard !Task.isCancelled, let packages = try? openPackages() else { return [] }
        return packages.flatMap { package in
            Task.isCancelled ? [] : (try? package.segments(in: box)) ?? []
        }
    }

    /// The features of the segments for the map. Each feature has the ID of
    /// its segment, whether the segment is collected, and its area. A
    /// cancelled task gets no features, like in `segments(in:)`.
    func features(of segments: [Segment], collected: Set<Segment.ID>) -> sending MLNShapeCollectionFeature {
        guard !Task.isCancelled else { return MLNShapeCollectionFeature(shapes: []) }
        return MLNShapeCollectionFeature(shapes: segments.map { segment in
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
