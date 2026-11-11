//
//  MapProjectionTests.swift
//  GassiPassCoreTests
//
//  Created by Maximilian Walterskirchen on 11.11.2026.
//

import CoreGraphics
import CoreLocation
import Testing
@testable import GassiPassCore

/// The projection of the small maps that the app draws itself. The tests
/// use a box near Dietikon that is twice as wide as it is high, in metres.
struct MapProjectionTests {
    let south = 47.40
    let north = 47.41
    let west = 8.40
    /// As far east as two times the height of the box.
    var east: Double { west + 2 * (north - south) / cos((south + north) / 2 * .pi / 180) }
    var corners: [CLLocationCoordinate2D] {
        [CLLocationCoordinate2D(latitude: south, longitude: west), CLLocationCoordinate2D(latitude: north, longitude: east)]
    }

    @Test func theCoordinatesFillTheRectangleWithNorthAtTheTop() {
        let project = MapProjection.fitting(corners, into: CGRect(x: 10, y: 20, width: 200, height: 100))

        let southWest = project(corners[0])
        let northEast = project(corners[1])
        #expect(abs(southWest.x - 10) < 1e-6)
        #expect(abs(southWest.y - 120) < 1e-6)
        #expect(abs(northEast.x - 210) < 1e-6)
        #expect(abs(northEast.y - 20) < 1e-6)
    }

    /// A square rectangle is too high for the box, so the box keeps its
    /// shape and sits in the middle.
    @Test func theCoordinatesKeepTheirShapeAndSitInTheMiddle() {
        let project = MapProjection.fitting(corners, into: CGRect(x: 0, y: 0, width: 200, height: 200))

        let southWest = project(corners[0])
        let northEast = project(corners[1])
        #expect(abs((northEast.x - southWest.x) - 200) < 1e-6)
        #expect(abs((southWest.y - northEast.y) - 100) < 1e-6)
        #expect(abs(northEast.y - 50) < 1e-6)
    }

    /// A track whose points are all the same has no extent.
    @Test func oneCoordinateLandsInsideTheRectangle() {
        let rect = CGRect(x: 0, y: 0, width: 80, height: 40)
        let project = MapProjection.fitting([corners[0], corners[0]], into: rect)

        let point = project(corners[0])
        #expect(point.x.isFinite && point.y.isFinite)
        #expect(rect.contains(point))
    }
}
