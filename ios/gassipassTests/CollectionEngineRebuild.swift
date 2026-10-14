//
//  CollectionEngineRebuild.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
@testable import gassipass

/// The rebuild mode without stored matches, for the tests of the rules. It
/// matches each walk on its own and adds up the matches, like `Collections`
/// does for the walks without a stored match.
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
        Self.collections(of: dogs, from: walks.map { (dogs: $0.dogs, match: match($0.track)) })
    }
}
