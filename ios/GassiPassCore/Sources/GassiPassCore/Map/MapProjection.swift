//
//  MapProjection.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 11.11.2026.
//

import CoreGraphics
import CoreLocation

/// Places coordinates on a flat drawing, for the small maps that the app
/// draws itself: the outline of an area and the thumbnail of a track.
public nonisolated enum MapProjection {
    /// A function that places coordinates in the rectangle, so that the
    /// given coordinates fill it as far as possible without distortion.
    /// North is at the top.
    public static func fitting(
        _ coordinates: [CLLocationCoordinate2D], into rect: CGRect
    ) -> (CLLocationCoordinate2D) -> CGPoint {
        let longitudes = coordinates.map(\.longitude), latitudes = coordinates.map(\.latitude)
        let minLongitude = longitudes.min() ?? 0, maxLongitude = longitudes.max() ?? 0
        let minLatitude = latitudes.min() ?? 0, maxLatitude = latitudes.max() ?? 0
        // A degree of longitude is shorter than a degree of latitude away
        // from the equator.
        let xScale = cos((minLatitude + maxLatitude) / 2 * .pi / 180)
        // Coordinates that are all the same have no extent. This smallest
        // extent, far below a millimetre, keeps the scale finite, so that
        // they land inside the rectangle.
        let smallestExtent = 1e-9
        let width = max((maxLongitude - minLongitude) * xScale, smallestExtent)
        let height = max(maxLatitude - minLatitude, smallestExtent)
        let pointsPerDegree = min(rect.width / width, rect.height / height)
        let offsetX = rect.minX + (rect.width - width * pointsPerDegree) / 2
        let offsetY = rect.minY + (rect.height - height * pointsPerDegree) / 2
        return { coordinate in
            CGPoint(x: offsetX + (coordinate.longitude - minLongitude) * xScale * pointsPerDegree,
                    y: offsetY + (maxLatitude - coordinate.latitude) * pointsPerDegree)
        }
    }
}
