//
//  CollectionHistory.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 25.10.2026.
//

import Foundation

/// The coverage histories of all dogs, and the walks that they hold, so that
/// an update adds only the walks that are new (ADR 0002). The app keeps it
/// with the stored matches (`WalkMatchCache`), so that also the first update
/// after a launch adds only the new walks.
nonisolated struct CollectionHistory: Codable, Equatable, Sendable {
    /// A walk that the histories hold.
    struct HeldWalk: Codable, Equatable, Sendable {
        /// The dogs whose histories hold the walk.
        var dogs: Set<UUID>
        /// Whether the walk covers a segment. A walk that covers none can
        /// leave without a rebuild.
        let coversSegments: Bool
    }

    private(set) var dogs: [UUID: CoverageHistory] = [:]
    private(set) var walks: [WalkMatchCache.Key: HeldWalk] = [:]

    /// The history to add the walks to, and the dogs that each walk adds to
    /// it. That is this history, or an empty one when a walk left it
    /// (`additions(for:dogs:)`): then all walks add their dogs.
    ///
    /// - Parameters:
    ///   - current: The dogs of each ended walk, of the dogs that have
    ///     collections.
    ///   - dogs: The dogs that have collections.
    func prepared(
        for current: [WalkMatchCache.Key: Set<UUID>], dogs: Set<UUID>
    ) -> (history: CollectionHistory, additions: [WalkMatchCache.Key: Set<UUID>]) {
        let additions = additions(for: current, dogs: dogs)
        var history = additions == nil ? CollectionHistory() : self
        history.keep(dogs: dogs, walks: current)
        return (history, additions ?? current.filter { !$0.value.isEmpty })
    }

    /// The dogs that each walk must add to the histories, so that they hold
    /// the walks and their dogs. It is nil when a walk that covers segments
    /// left the history of one of the dogs, because the walk was deleted or
    /// the dog was removed from it: then only a rebuild from all walks gives
    /// the right collections. A dog that leaves takes its history with it,
    /// so it needs no rebuild.
    ///
    /// - Parameters:
    ///   - current: The dogs of each ended walk, of the dogs that have
    ///     collections.
    ///   - dogs: The dogs that have collections.
    private func additions(
        for current: [WalkMatchCache.Key: Set<UUID>], dogs: Set<UUID>
    ) -> [WalkMatchCache.Key: Set<UUID>]? {
        for (key, held) in walks where held.coversSegments {
            let left = held.dogs.intersection(dogs).subtracting(current[key] ?? [])
            if !left.isEmpty { return nil }
        }
        var additions: [WalkMatchCache.Key: Set<UUID>] = [:]
        for (key, walkDogs) in current {
            let new = walkDogs.subtracting(walks[key]?.dogs ?? [])
            if !new.isEmpty {
                additions[key] = new
            }
        }
        return additions
    }

    /// Keeps the histories of the dogs, with an empty one for a dog that has
    /// none. The held walks keep only these dogs and the dogs that they
    /// still have, so that a walk that leaves is no longer held.
    mutating func keep(dogs kept: Set<UUID>, walks current: [WalkMatchCache.Key: Set<UUID>]) {
        dogs = dogs.filter { kept.contains($0.key) }
        for dog in kept where dogs[dog] == nil {
            dogs[dog] = CoverageHistory()
        }
        walks = Dictionary(uniqueKeysWithValues: walks.compactMap { key, held in
            var held = held
            held.dogs.formIntersection(kept.intersection(current[key] ?? []))
            return held.dogs.isEmpty ? nil : (key, held)
        })
    }

    /// Adds the match of the walk to the histories of the dogs.
    mutating func add(_ match: WalkMatch, of key: WalkMatchCache.Key, for walkDogs: Set<UUID>) {
        let walkDogs = walkDogs.intersection(dogs.keys)
        guard !walkDogs.isEmpty else { return }
        for dog in walkDogs {
            dogs[dog]!.add(match)
        }
        let coversSegments = (walks[key]?.coversSegments ?? false) || !match.entries.isEmpty
        walks[key] = HeldWalk(dogs: walkDogs.union(walks[key]?.dogs ?? []), coversSegments: coversSegments)
    }

    /// The collection of each dog.
    var collections: [UUID: DogCollection] {
        dogs.mapValues(\.collection)
    }
}
