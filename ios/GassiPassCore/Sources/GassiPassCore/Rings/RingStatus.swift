//
//  RingStatus.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import Foundation

/// The current ring of a dog, for the ring card and the map around the home
/// base.
public struct RingStatus: Equatable {
    /// The map shows this many of the nearest new segments.
    public static let nearestNewSegmentCount = 10

    public let ring: Ring
    public let completion: Completion
    /// The segments that the dog has not collected, the nearest to the home
    /// base first. The first one gives the distance on the ring card.
    public let nearestNewSegments: [RingSegment]

    public init(ring: Ring, completion: Completion, nearestNewSegments: [RingSegment]) {
        self.ring = ring
        self.completion = completion
        self.nearestNewSegments = nearestNewSegments
    }
}
