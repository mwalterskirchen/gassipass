//
//  Track.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import Foundation

/// One raw GPS point of a walk, as Core Location delivers it.
nonisolated struct TrackPoint: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    /// The radius of uncertainty in metres.
    let horizontalAccuracy: Double

    init(latitude: Double, longitude: Double, timestamp: Date, horizontalAccuracy: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
    }

    init(location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
            timestamp: location.timestamp, horizontalAccuracy: location.horizontalAccuracy)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distance(to other: TrackPoint) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

/// The raw GPS points of one walk, in the order of recording.
///
/// The app stores the track of every walk permanently, because the collection
/// is calculated from the walks (ADR 0002).
nonisolated struct Track: Equatable, Sendable {
    enum Error: Swift.Error {
        case unsupportedFormatVersion(UInt8?)
        case truncated
    }

    /// Version 1 stores each point as four little-endian doubles: latitude,
    /// longitude, timestamp (seconds since 2001-01-01) and horizontal accuracy.
    static let formatVersion: UInt8 = 1
    private static let bytesPerPoint = 4 * MemoryLayout<Double>.size

    var points: [TrackPoint]

    init(points: [TrackPoint] = []) {
        self.points = points
    }

    init(data: Data) throws {
        guard data.first == Self.formatVersion else {
            throw Error.unsupportedFormatVersion(data.first)
        }
        let body = data.dropFirst()
        guard body.count.isMultiple(of: Self.bytesPerPoint) else { throw Error.truncated }
        points = body.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: Self.bytesPerPoint).map { offset in
                func double(_ index: Int) -> Double {
                    Double(bitPattern: UInt64(littleEndian: bytes.loadUnaligned(
                        fromByteOffset: offset + index * MemoryLayout<Double>.size, as: UInt64.self)))
                }
                return TrackPoint(
                    latitude: double(0), longitude: double(1),
                    timestamp: Date(timeIntervalSinceReferenceDate: double(2)),
                    horizontalAccuracy: double(3))
            }
        }
    }

    var coordinates: [CLLocationCoordinate2D] {
        points.map(\.coordinate)
    }

    /// The length of the line through all points, in metres.
    var distanceMetres: Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    var data: Data {
        var data = Data([Self.formatVersion])
        data.reserveCapacity(1 + points.count * Self.bytesPerPoint)
        for point in points {
            for value in [point.latitude, point.longitude,
                          point.timestamp.timeIntervalSinceReferenceDate, point.horizontalAccuracy] {
                withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
        }
        return data
    }
}
