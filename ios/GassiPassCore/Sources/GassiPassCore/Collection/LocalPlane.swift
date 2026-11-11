//
//  LocalPlane.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import Foundation

/// A flat plane in metres around one point. Across the size of a segment the
/// error of this projection is far below the accuracy of GPS.
public nonisolated struct LocalPlane: Sendable {
    public static let metresPerDegreeLatitude = 6_371_008.8 * Double.pi / 180

    public let latitude: Double
    public let longitude: Double
    public let metresPerDegreeLongitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        metresPerDegreeLongitude = Self.metresPerDegreeLatitude * cos(latitude * .pi / 180)
    }

    /// A distance in metres as degrees of latitude and of longitude.
    public static func degrees(metres: Double, atLatitude latitude: Double) -> (latitude: Double, longitude: Double) {
        (metres / metresPerDegreeLatitude,
         metres / LocalPlane(latitude: latitude, longitude: 0).metresPerDegreeLongitude)
    }

    public func point(latitude: Double, longitude: Double) -> SIMD2<Double> {
        SIMD2((longitude - self.longitude) * metresPerDegreeLongitude,
              (latitude - self.latitude) * Self.metresPerDegreeLatitude)
    }
}

nonisolated extension SIMD2<Double> {
    /// The length of the vector, in metres on a `LocalPlane`.
    public var length: Double { (self * self).sum().squareRoot() }
}
