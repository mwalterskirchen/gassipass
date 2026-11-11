//
//  CollectionInput.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation

/// What the collections are built from: the dogs, and the ended walks with
/// their dogs.
public nonisolated struct CollectionInput: Codable, Equatable, Sendable {
    public let dogs: Set<UUID>
    public let walks: [WalkInput]

    @MainActor
    public init(dogs: [Dog], walks: [Walk]) {
        self.dogs = Set(dogs.map(\.id))
        self.walks = walks.map {
            WalkInput(walk: $0.id, key: WalkMatchCache.Key($0), dogs: Set($0.dogs.map(\.id)))
        }
    }

    public init(data: Data) throws {
        self = try PropertyListDecoder().decode(Self.self, from: data)
    }

    public func data() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    /// The ended walks of each dog.
    public var walksByDog: [UUID: Set<UUID>] {
        var walkIDs: [UUID: Set<UUID>] = [:]
        for walk in walks {
            for dog in walk.dogs {
                walkIDs[dog, default: []].insert(walk.walk)
            }
        }
        return walkIDs
    }
}

public nonisolated struct WalkInput: Codable, Equatable, Sendable {
    public let walk: UUID
    /// The key of the match changes when the track of the walk arrives after
    /// the walk, or when the distance is calculated again.
    public let key: WalkMatchCache.Key?
    public let dogs: Set<UUID>

    public init(walk: UUID, key: WalkMatchCache.Key?, dogs: Set<UUID>) {
        self.walk = walk
        self.key = key
        self.dogs = dogs
    }
}
