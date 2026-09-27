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

    var isRecording: Bool {
        endedAt == nil
    }

    var track: Track {
        get { trackData.flatMap { try? Track(data: $0) } ?? Track() }
        set {
            trackData = newValue.data
            distanceMetres = newValue.distanceMetres
        }
    }

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }

    var sortedDogNames: [String] {
        (dogs ?? []).map(\.name).sorted()
    }
}
