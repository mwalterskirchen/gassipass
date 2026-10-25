//
//  CollectionEngineRebuild.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
@testable import gassipass

/// The rebuild mode without stored matches, for the tests of the rules. It
/// matches each walk on its own and adds the matches to a new history, like
/// `Collections` does for the walks without a stored match.
extension CollectionEngine {
    /// A walk as the tests give it to the engine: its raw track and the dogs
    /// that take part.
    struct Walk<Dog: Hashable & Sendable>: Sendable {
        let dogs: Set<Dog>
        let track: Track
    }

    /// The collection of each of the dogs, from all their walks. A dog
    /// collects nothing from a walk that it did not take part in.
    func rebuild<Dog>(dogs: Set<Dog>, walks: [Walk<Dog>]) -> [Dog: DogCollection] {
        let ids = Dictionary(uniqueKeysWithValues: dogs.map { ($0, UUID()) })
        var current: [WalkMatchCache.Key: Set<UUID>] = [:]
        var matches: [WalkMatchCache.Key: WalkMatch] = [:]
        for (index, walk) in walks.enumerated() {
            // The index keeps the keys of walks with the same times apart.
            let key = WalkMatchCache.Key(
                startedAt: walk.track.points.first?.timestamp ?? .distantPast,
                endedAt: walk.track.points.last?.timestamp ?? .distantPast, distanceMetres: Double(index))
            current[key] = Set(walk.dogs.compactMap { ids[$0] })
            matches[key] = match(walk.track)
        }
        var (history, additions) = CollectionHistory().prepared(for: current, dogs: Set(ids.values))
        for (key, walkDogs) in additions.sorted(by: { $0.key.startedAt < $1.key.startedAt }) {
            history.add(matches[key]!, of: key, for: walkDogs)
        }
        let collections = history.collections
        return ids.mapValues { collections[$0] ?? DogCollection() }
    }
}
