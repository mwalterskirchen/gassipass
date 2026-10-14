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

    /// The name of a pack that has no name of its own.
    static var defaultName: String {
        String(localized: "My Pack")
    }
}
