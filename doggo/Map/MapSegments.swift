//
//  MapSegments.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import MapLibre

/// Opens the bundled map packages for `SegmentMapView`, and builds the
/// features of a list of segments for the map, off the main thread. The map
/// draws all other segments from the tiles of the packages.
actor MapSegments {
    /// The one reader of all map views, so that the packages open only once.
    static let shared = MapSegments()

    /// The packages, or the error that stopped them from opening, after the first use.
    private var packages: Result<[MapPackage], any Error>?

    /// Opens the packages, unless they are open already. It checks that the
    /// map can read them before it draws their tiles.
    func open() throws {
        if packages == nil {
            packages = Result { try MapPackage.bundled() }
        }
        _ = try packages!.get()
    }

    /// The features of the segments for the map. Each feature has the ID of
    /// its segment. A cancelled task gets no features, because a newer list
    /// replaces it.
    func features(of segments: [Segment]) -> sending MLNShapeCollectionFeature {
        guard !Task.isCancelled else { return MLNShapeCollectionFeature(shapes: []) }
        return MLNShapeCollectionFeature(shapes: segments.map { segment in
            var coordinates = segment.coordinates
            let feature = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
            feature.identifier = segment.id
            return feature
        })
    }
}
