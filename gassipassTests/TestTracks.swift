//
//  TestTracks.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import Foundation
@testable import gassipass

/// A synthetic walk along a part of a segment, from `from` to `to` as shares
/// of its length. It has a point every 5 m, at the given speed, at
/// the given distance to the left of the segment.
func syntheticTrack(
    along segment: Segment, from: Double = 0, to: Double = 1,
    metresPerSecond speed: Double = 1.4, leftMetres offset: Double = 0,
    accuracy: Double = 5, startingAt startTime: Date
) -> Track {
    let line = LineInMetres(segment)
    let first = from * line.length, last = to * line.length
    let count = max(Int((abs(last - first) / 5).rounded(.up)), 1)
    let points = (0...count).map { index in
        let along = first + (last - first) * Double(index) / Double(count)
        return line.point(at: along, leftMetres: offset, accuracy: accuracy,
                          timestamp: startTime + abs(along - first) / speed)
    }
    return Track(points: points)
}

/// A straight segment that starts at the given point and runs east, for
/// tests that need a small invented area.
func straightSegment(
    id: String, fid: Int = 0, area: Int, street: String? = nil, startLatitude: Double, startLongitude: Double, eastMetres: Double
) -> Segment {
    let end = startLongitude + eastMetres / LineInMetres.metresPerDegreeLongitude(atLatitude: startLatitude)
    return Segment(
        id: id, fid: fid, area: area, wayClass: "2m Weg", street: street, lengthMetres: eastMetres,
        coordinates: [CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude),
                      CLLocationCoordinate2D(latitude: startLatitude, longitude: end)])
}

/// A segment in metres on a flat local plane, for building test tracks. It
/// uses its own simple projection, not the one of the engine.
struct LineInMetres {
    static let metresPerDegreeLatitude = 111_195.0

    static func metresPerDegreeLongitude(atLatitude latitude: Double) -> Double {
        metresPerDegreeLatitude * cos(latitude * .pi / 180)
    }

    let origin: (latitude: Double, longitude: Double)
    let metresPerDegreeLongitude: Double
    let points: [(x: Double, y: Double)]

    init(_ segment: Segment) {
        let first = segment.coordinates[0]
        origin = (first.latitude, first.longitude)
        let metresPerDegreeLongitude = Self.metresPerDegreeLongitude(atLatitude: first.latitude)
        self.metresPerDegreeLongitude = metresPerDegreeLongitude
        points = segment.coordinates.map {
            (($0.longitude - first.longitude) * metresPerDegreeLongitude,
             ($0.latitude - first.latitude) * Self.metresPerDegreeLatitude)
        }
    }

    var length: Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    func point(at along: Double, leftMetres offset: Double, accuracy: Double, timestamp: Date) -> TrackPoint {
        let legs = zip(points, points.dropFirst()).filter { hypot($1.x - $0.x, $1.y - $0.y) > 0 }
        var remaining = along
        for (index, (a, b)) in legs.enumerated() {
            let leg = hypot(b.x - a.x, b.y - a.y)
            if remaining <= leg || index == legs.count - 1 {
                let t = min(max(remaining / leg, 0), 1)
                let (dx, dy) = ((b.x - a.x) / leg, (b.y - a.y) / leg)
                return trackPoint(x: a.x + t * (b.x - a.x) - dy * offset,
                                  y: a.y + t * (b.y - a.y) + dx * offset,
                                  accuracy: accuracy, timestamp: timestamp)
            }
            remaining -= leg
        }
        preconditionFailure("A segment has at least one leg")
    }

    private func trackPoint(x: Double, y: Double, accuracy: Double, timestamp: Date) -> TrackPoint {
        TrackPoint(latitude: origin.latitude + y / Self.metresPerDegreeLatitude,
                   longitude: origin.longitude + x / metresPerDegreeLongitude,
                   timestamp: timestamp, horizontalAccuracy: accuracy)
    }
}
