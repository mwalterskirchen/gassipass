//
//  MapPackagesEngine.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import CoreLocation
import Foundation

/// The engines that the app matches with. The packages are too big to load
/// at once, so an engine gets only the segments that it needs: the segments
/// in the `coverableBoxes(of:)` of the tracks, and for the live mode also
/// the segments in the `box(around:withinMetres:)` of the walker.
nonisolated extension MapPackages {
    /// An engine for matching the tracks.
    func engine(covering tracks: [Track]) throws -> CollectionEngine {
        CollectionEngine(segments: try segments(in: tracks.flatMap(CollectionEngine.coverableBoxes(of:))))
    }

    /// An engine for the live mode near the point, which can also match the
    /// track so far.
    func engine(
        around point: CLLocationCoordinate2D, withinMetres radius: Double, covering track: Track = Track()
    ) throws -> CollectionEngine {
        let boxes = CollectionEngine.coverableBoxes(of: track) + [CollectionEngine.box(around: point, withinMetres: radius)]
        return CollectionEngine(segments: try segments(in: boxes))
    }
}
