//
//  CompletedRing.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import Foundation
import SwiftData

extension CompletedRing {
    public convenience init(dogID: UUID, ring: Ring, completedAt: Date, context: ModelContext) {
        self.init(
            dogID: dogID, number: ring.number, radiusMetres: ring.radiusMetres,
            centreLatitude: ring.centre.latitude, centreLongitude: ring.centre.longitude, completedAt: completedAt)
        context.insert(self)
    }

    /// The ring, around the home base of the time of the stamp.
    public var ring: Ring {
        Ring(number: number, centre: HomeBase(latitude: centreLatitude, longitude: centreLongitude))
    }

    /// The ring stamp as a record of the collection engine.
    public var record: CompletedRecord<UUID, Ring> {
        CompletedRecord(dog: dogID, goal: ring, date: completedAt)
    }
}

extension Pack {
    /// The home base of the pack, or nil until a member sets it.
    public var homeBase: HomeBase? {
        guard let homeLatitude, let homeLongitude else { return nil }
        return HomeBase(latitude: homeLatitude, longitude: homeLongitude)
    }

    /// Sets the home base, and notes the change, so that it uploads. The
    /// rings move with it, and the ring stamps of the old home base stay.
    public func setHomeBase(_ homeBase: HomeBase, at date: Date) {
        homeLatitude = homeBase.latitude
        homeLongitude = homeBase.longitude
        homeSetAt = date
        isHomeBaseWaitingToUpload = true
        noteChange(at: date)
    }
}

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
