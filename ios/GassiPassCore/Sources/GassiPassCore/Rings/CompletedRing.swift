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
