//
//  Walk.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import SwiftData

/// One recording of a GPS track, together with the dogs that take part.
///
/// The raw track is stored permanently (ADR 0002). A walk that is still being
/// recorded has no end date, so a recording can continue after the app was
/// terminated. A deleted walk stays in the store with its deletion time
/// (`UploadingRow`), and the app no longer shows it.
extension Walk {
    convenience init(startedAt: Date, dogs: some Sequence<Dog>, context: ModelContext) {
        self.init(startedAt: startedAt)
        context.insert(self)
        for dog in dogs {
            context.insert(WalkDog(walk: self, dog: dog))
        }
    }

    /// The ended walks, the newest first. A walk that is still being
    /// recorded has no end date.
    static func ended() -> FetchDescriptor<Walk> {
        FetchDescriptor(
            predicate: #Predicate { $0.endedAt != nil && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
    }

    /// The walks without an end date that this device continues: its own,
    /// and the walks from before iCloud sync.
    static func unfinished(onDevice deviceID: String) -> FetchDescriptor<Walk> {
        FetchDescriptor(predicate: #Predicate {
            $0.endedAt == nil && $0.deletedAt == nil && ($0.deviceID == deviceID || $0.deviceID == "")
        })
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
        store(track, distanceMetres: track.distanceMetres)
    }

    /// Stores the track with its distance, which the caller already knows.
    func store(_ track: Track, distanceMetres: Double) {
        trackData = track.data
        self.distanceMetres = distanceMetres
        distanceVersion = WalkDistance.version
    }

    /// Calculates the distance again from the track for each walk whose
    /// distance comes from older rules. A walk whose track cannot be read
    /// keeps its distance. A walk from another device with a newer build
    /// keeps the distance of the newer rules.
    static func updateDistances(in context: ModelContext) throws {
        let version = WalkDistance.version
        let outdated = FetchDescriptor<Walk>(predicate: #Predicate { $0.distanceVersion < version })
        for walk in try context.fetch(outdated) {
            guard let track = try? walk.readTrack() else { continue }
            walk.distanceMetres = track.distanceMetres
            walk.distanceVersion = version
            walk.noteChange()
        }
        if context.hasChanges {
            try context.save()
        }
    }

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }

    /// The dogs that take part in the walk.
    var dogs: [Dog] {
        (walkDogs ?? []).compactMap { $0.deletedAt == nil ? $0.dog : nil }
    }

    /// Makes the dogs the dogs of the walk. The row of a dog that leaves the
    /// walk is marked as deleted, and a dog that comes back gets its row
    /// back, so that each dog has at most one row in the walk.
    func changeDogs(to dogs: some Collection<Dog>, at date: Date = .now) {
        guard let context = modelContext else { return }
        var added = Set(dogs.map(\.id))
        for walkDog in walkDogs ?? [] {
            guard let dog = walkDog.dog else { continue }
            let takesPart = added.remove(dog.id) != nil
            if takesPart, walkDog.deletedAt != nil {
                walkDog.deletedAt = nil
                walkDog.noteChange(at: date)
            } else if !takesPart, walkDog.deletedAt == nil {
                walkDog.markDeleted(at: date)
            }
        }
        for dog in dogs where added.remove(dog.id) != nil {
            context.insert(WalkDog(walk: self, dog: dog))
        }
    }

    /// Whether the dog takes part in the walk.
    func hasDog(_ dog: Dog) -> Bool {
        dogs.contains { $0.id == dog.id }
    }

    /// The names of the dogs as a list, for example "Bello and Luna".
    var dogNames: String {
        dogs.map(\.name).sorted().formatted(.list(type: .and))
    }
}
