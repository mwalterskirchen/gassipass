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

    /// The name that the app shows for the pack.
    var shownName: String {
        name.isEmpty ? Self.defaultName : name
    }

    /// The name of a pack that has no name of its own. It becomes
    /// "Rudel von <first name of the pack owner>" when the share of the pack
    /// tells the name (#73).
    static var defaultName: String {
        String(localized: "My Pack")
    }
}

extension Pack: Identifiable {}
