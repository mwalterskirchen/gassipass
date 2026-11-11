//
//  Dog.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import SwiftData

/// The owner of a collection. Each dog has its own collection and its own
/// completions.
///
/// The app never deletes a dog. A dog that no longer takes part in walks
/// becomes a retired dog, and its collection, completions and completed
/// records stay.
extension Dog {
    public convenience init(name: String, context: ModelContext) {
        self.init(name: name)
        context.insert(self)
    }

    /// All dogs, sorted by name in the order of the Finder.
    public static func all() -> FetchDescriptor<Dog> {
        FetchDescriptor(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.name, comparator: .localizedStandard)])
    }

    /// The dogs from before the packs, which have no pack yet.
    public static func withoutPack() -> FetchDescriptor<Dog> {
        FetchDescriptor(predicate: #Predicate { $0.pack == nil && $0.deletedAt == nil })
    }

    /// The dogs that the member who starts a walk can choose, sorted by name.
    public static func canJoinWalks() -> FetchDescriptor<Dog> {
        var descriptor = all()
        descriptor.predicate = #Predicate { $0.retiredAt == nil && $0.deletedAt == nil }
        return descriptor
    }

    public var isRetired: Bool {
        retiredAt != nil
    }

    public func retire(on date: Date, reason: String) {
        retiredAt = date
        retirementReason = reason
    }

    /// Makes a retired dog take part in walks again, for example after the
    /// user retired it by mistake.
    public func unretire() {
        retiredAt = nil
        retirementReason = ""
    }

    /// The walks that the dog takes part in, also a walk that is still being
    /// recorded.
    public var walks: [Walk] {
        (walkDogs ?? []).compactMap { walkDog in
            guard walkDog.deletedAt == nil, let walk = walkDog.walk, walk.deletedAt == nil else { return nil }
            return walk
        }
    }
}
