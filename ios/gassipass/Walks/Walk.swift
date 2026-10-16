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
/// The raw track is stored permanently (ADR 0002), until the walk is
/// deleted. A walk that is still being recorded has no end date, so a
/// recording can continue after the app was terminated. A deleted walk stays
/// in the store with its deletion time, without its track (`UploadingRow`),
/// and the app no longer shows it.
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

    /// The walks that are still being recorded. An unfinished walk never
    /// leaves its phone (ADR 0006), so each one is a walk of this phone, also
    /// after a backup that the user restored to a new phone.
    static func unfinished() -> FetchDescriptor<Walk> {
        FetchDescriptor(predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil })
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

    /// Whether the walk is still in the store. The store removes it, for
    /// example, with its pack, and its values can then no longer be read.
    var isInStore: Bool {
        modelContext != nil && !isDeleted
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

    /// Deletes the walk. Its GPS track leaves the phone, and the upload takes
    /// it off the server, so that nobody can read the route any more. The
    /// walk stays in the store with the deletion time, like every row that
    /// uploads (`UploadingRow.markDeleted(at:)`, which this hides for a
    /// walk).
    func markDeleted(at date: Date = .now) {
        trackData = nil
        deletedAt = date
        noteChange(at: date)
    }

    /// Whether the dog takes part in the walk.
    func hasDog(_ dog: Dog) -> Bool {
        dogs.contains { $0.id == dog.id }
    }

    /// The names of the dogs as a list, for example "Bello and Luna".
    var dogNames: String {
        dogs.map(\.name).sorted().formatted(.list(type: .and))
    }

    /// The name of the member who recorded the walk, or nil for a walk with
    /// an empty name. A walk from before the accounts has an empty name
    /// until it uploads, and the server then gives it the name of the
    /// member who uploads it.
    var shownMemberName: String? {
        memberName.isEmpty ? nil : memberName
    }
}
