//
//  CompletedRing.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import Foundation
import SwiftData

extension CompletedRing {
    convenience init(dogID: UUID, ring: Ring, completedAt: Date, context: ModelContext) {
        self.init(
            dogID: dogID, number: ring.number, radiusMetres: ring.radiusMetres,
            centreLatitude: ring.centre.latitude, centreLongitude: ring.centre.longitude, completedAt: completedAt)
        context.insert(self)
    }

    /// The ring, around the home base of the time of the stamp.
    var ring: Ring {
        Ring(number: number, centre: HomeBase(latitude: centreLatitude, longitude: centreLongitude))
    }

    /// The ring stamp as a record of the collection engine.
    var record: CompletedRecord<UUID, Ring> {
        CompletedRecord(dog: dogID, goal: ring, date: completedAt)
    }
}

extension Pack {
    /// The home base of the pack, or nil until a member sets it.
    var homeBase: HomeBase? {
        guard let homeLatitude, let homeLongitude else { return nil }
        return HomeBase(latitude: homeLatitude, longitude: homeLongitude)
    }

    /// Sets the home base, and notes the change, so that it uploads. The
    /// rings move with it, and the ring stamps of the old home base stay.
    func setHomeBase(_ homeBase: HomeBase, at date: Date) {
        homeLatitude = homeBase.latitude
        homeLongitude = homeBase.longitude
        homeSetAt = date
        isHomeBaseWaitingToUpload = true
        noteChange(at: date)
    }
}

/// The current ring of a dog, for the ring card and the map around the home
/// base.
struct RingStatus: Equatable {
    /// The map shows this many of the nearest new segments.
    static let nearestNewSegmentCount = 10

    let ring: Ring
    let completion: Completion
    /// The share of the collected length in the ring with a mark of the
    /// last four weeks.
    let markedShare: Double
    /// The segments that the dog has not collected, the nearest to the home
    /// base first. The first one gives the distance on the ring card.
    let nearestNewSegments: [RingSegment]
}
