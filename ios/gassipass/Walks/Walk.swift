//
//  Walk.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreData

/// One recording of a GPS track, together with the dogs that take part.
///
/// The raw track is stored permanently (ADR 0002). A walk that is still being
/// recorded has no end date, so a recording can continue after the app was
/// terminated.
///
/// The entity in the Core Data model follows the CloudKit rules (`Stores`).
@objc(Walk)
final class Walk: NSManagedObject {
    @NSManaged var startedAt: Date
    @NSManaged var endedAt: Date?
    /// The raw track, encoded by `Track`.
    @NSManaged var trackData: Data?
    /// A cache of the track's distance, so the walk list does not decode
    /// every track.
    @NSManaged var distanceMetres: Double
    /// The version of the rules (`WalkDistance.version`) that calculated
    /// the distance. Walks from before the first version have 0.
    @NSManaged var distanceVersion: Int
    /// The last time the walker answered that the walk has not ended yet,
    /// or nil. The question whether the walk has ended waits for an hour
    /// after it, also after a relaunch.
    @NSManaged var continuedAt: Date?
    /// The device that records the walk (`ThisDevice.id`). Only this device
    /// continues the walk while it has no end date. A walk from before iCloud
    /// sync has an empty ID and counts as a walk of every device.
    @NSManaged var deviceID: String
    /// The first name of the member who recorded the walk, from their
    /// iCloud identity, so that it stays after the member leaves the pack.
    /// An empty name means the pack owner, which covers the walks from
    /// before the pack. Use `Packs.shownMemberName(of:)` to show it.
    @NSManaged var memberName: String
    @NSManaged var dogs: Set<Dog>

    convenience init(startedAt: Date, dogs: some Sequence<Dog>, context: NSManagedObjectContext) {
        self.init(context: context)
        self.startedAt = startedAt
        self.dogs = Set(dogs)
    }

    /// A request for the ended walks, the newest first. A walk that is still
    /// being recorded has no end date.
    static func ended() -> NSFetchRequest<Walk> {
        let request = NSFetchRequest<Walk>(entityName: "Walk")
        request.predicate = NSPredicate(format: "endedAt != nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Walk.startedAt, ascending: false)]
        return request
    }

    /// A request for the walks without an end date that this device
    /// continues: its own, and the walks from before iCloud sync.
    static func unfinished(onDevice deviceID: String) -> NSFetchRequest<Walk> {
        let request = NSFetchRequest<Walk>(entityName: "Walk")
        request.predicate = NSPredicate(
            format: "endedAt == nil AND (deviceID == %@ OR deviceID == %@)", deviceID, "")
        return request
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
    static func updateDistances(in context: NSManagedObjectContext) throws {
        let version = WalkDistance.version
        let outdated = NSFetchRequest<Walk>(entityName: "Walk")
        outdated.predicate = NSPredicate(format: "distanceVersion < %@", version as NSNumber)
        for walk in try context.fetch(outdated) {
            guard let track = try? walk.readTrack() else { continue }
            walk.distanceMetres = track.distanceMetres
            walk.distanceVersion = version
        }
        if context.hasChanges {
            try context.save()
        }
    }

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }

    /// Whether the dog takes part in the walk.
    func hasDog(_ dog: Dog) -> Bool {
        dogs.contains(dog)
    }

    /// The names of the dogs as a list, for example "Bello and Luna".
    var dogNames: String {
        dogs.map(\.name).sorted().formatted(.list(type: .and))
    }
}

/// The identity of the object, which stays the same when its object ID
/// changes from a temporary to a permanent ID at the first save.
extension Walk: Identifiable {}
