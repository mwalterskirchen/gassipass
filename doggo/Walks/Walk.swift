//
//  Walk.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import SwiftData

/// One recording of a GPS track, together with the dogs that take part.
///
/// The raw track is stored permanently (ADR 0002). A walk that is still being
/// recorded has no end date, so a recording can continue after the app was
/// terminated.
///
/// The model follows the CloudKit rules of SwiftData, like `Dog`.
@Model
final class Walk {
    var startedAt: Date = Date.now
    var endedAt: Date?
    /// The raw track, encoded by `Track`.
    @Attribute(.externalStorage)
    var trackData: Data?
    /// A cache of the track's distance, so the walk list does not decode
    /// every track.
    var distanceMetres: Double = 0
    var dogs: [Dog]? = []

    init(startedAt: Date, dogs: [Dog]) {
        self.startedAt = startedAt
        self.dogs = dogs
    }

    /// The stored track for display. A track that cannot be read shows as
    /// empty. Code that writes the track back uses `readTrack()`, so that it
    /// never replaces stored points that it could not read.
    var track: Track {
        (try? readTrack()) ?? Track()
    }

    func readTrack() throws -> Track {
        try trackData.map(Track.init(data:)) ?? Track()
    }

    func store(_ track: Track) {
        trackData = track.data
        distanceMetres = track.distanceMetres
    }

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }

    /// The names of the dogs as a list, for example "Bello and Luna".
    var dogNames: String {
        (dogs ?? []).map(\.name).sorted().formatted(.list(type: .and))
    }
}
