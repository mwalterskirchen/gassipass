//
//  Pack.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import CoreData

/// A group of members and the dogs that they walk together. Every dog
/// belongs to one pack, and everything about the dog is shared in it.
///
/// The app makes and changes packs only through `Packs`. The entity follows
/// the CloudKit rules (`Stores`).
@objc(Pack)
final class Pack: NSManagedObject {
    /// The name that a member gave the pack, or empty for the default name.
    @NSManaged var name: String
    @NSManaged var createdAt: Date
    /// A random ID that decides which pack stays when two packs of the same
    /// person have the same creation date, so that every phone keeps the
    /// same one.
    @NSManaged var randomID: String
    /// Whether the pack owner has shared the pack. `Packs` sets it before it
    /// makes the share, and it stays set. It travels in the record of the
    /// pack, so a phone that gets the pack before its share knows that the
    /// pack is shared.
    @NSManaged var isShared: Bool
    @NSManaged var dogs: Set<Dog>

    /// A request for all packs, the first made first.
    static func all() -> NSFetchRequest<Pack> {
        let request = NSFetchRequest<Pack>(entityName: "Pack")
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(Pack.createdAt), ascending: true),
            NSSortDescriptor(key: #keyPath(Pack.randomID), ascending: true),
        ]
        return request
    }

    /// The name of a pack that has no name of its own: "Rudel von <first
    /// name of the pack owner>", or "Mein Rudel" while the app does not know
    /// the name. CloudKit tells the name only through the share of the pack.
    static func defaultName(packOwnerFirstName: String?) -> String {
        guard let packOwnerFirstName, !packOwnerFirstName.isEmpty else {
            return String(localized: "My Pack")
        }
        return String(localized: "Pack of \(packOwnerFirstName)")
    }
}

extension Pack: Identifiable {}
