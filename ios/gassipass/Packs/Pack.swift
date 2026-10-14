//
//  Pack.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import Foundation
import SwiftData

/// A group of members and the dogs that they walk together. Every dog
/// belongs to one pack, and everything about the dog is shared in it.
///
/// The app makes and changes packs through `Packs`. `Account` notes that a
/// pack has uploaded, and moves the dogs of this phone into the pack of the
/// account (ADR 0005). `PackDownload` stores the pack of the account.
extension Pack {
    /// All packs, the first made first.
    static func all() -> FetchDescriptor<Pack> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt)])
    }

    /// The pack of this phone, or nil before the first dog. A person is a
    /// member of at most one pack (ADR 0005).
    static func ofThisPhone(in context: ModelContext) throws -> Pack? {
        var descriptor = all()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The name of a pack that has no name of its own.
    static var defaultName: String {
        String(localized: "My Pack")
    }

    /// The name that the app shows for a pack with the name.
    static func shownName(_ name: String) -> String {
        name.isEmpty ? defaultName : name
    }

    /// The name that the app shows for the pack.
    var shownName: String {
        Self.shownName(name)
    }
}
