//
//  ServerWalkDog.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// One dog that takes part in one walk, on the server.
public nonisolated struct ServerWalkDog: ServerRow, Equatable {
    public static let table = ServerTable.walkDogs

    public var id: UUID
    public var packID: UUID
    public var walkID: UUID
    public var dogID: UUID
    public var deletedAt: Date?

    public enum CodingKeys: String, CodingKey {
        case id
        case packID = "pack_id"
        case walkID = "walk_id"
        case dogID = "dog_id"
        case deletedAt = "deleted_at"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(packID, forKey: .packID)
        try container.encode(walkID, forKey: .walkID)
        try container.encode(dogID, forKey: .dogID)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    public init(id: UUID, packID: UUID, walkID: UUID, dogID: UUID, deletedAt: Date? = nil) {
        self.id = id
        self.packID = packID
        self.walkID = walkID
        self.dogID = dogID
        self.deletedAt = deletedAt
    }
}

extension ServerWalkDog: SyncedRow {
    public static var waitingRows: FetchDescriptor<WalkDog> {
        FetchDescriptor(predicate: #Predicate<WalkDog> { $0.isWaitingToUpload })
    }

    /// A dog of a walk that is still being recorded does not count, because
    /// it uploads only after the walk ends.
    public static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<WalkDog> {
        FetchDescriptor(predicate: #Predicate<WalkDog> {
            $0.isWaitingToUpload && $0.walk?.endedAt != nil && $0.changedAt > start && $0.changedAt <= end
        })
    }

    public static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<WalkDog> {
        FetchDescriptor(predicate: #Predicate<WalkDog> { ids.contains($0.id) })
    }

    public static func targets(of local: WalkDog) -> [SyncedTarget]? {
        guard let walk = local.walk, let dog = local.dog else { return nil }
        return [.walk(walk.id), .dog(dog.id)]
    }

    public var targets: [SyncedTarget] {
        [.walk(walkID), .dog(dogID)]
    }

    public init?(_ local: WalkDog, packID: UUID, filePath: String?) {
        guard let walk = local.walk, let dog = local.dog else { return nil }
        self.init(id: local.id, packID: packID, walkID: walk.id, dogID: dog.id, deletedAt: local.deletedAt)
    }

    public func store(in local: WalkDog?, targets: StoreTargets) throws -> WalkDog {
        let walk = try targets.local(ServerWalk.self, walkID)
        let dog = try targets.local(ServerDog.self, dogID)
        let walkDog = local ?? WalkDog(id: id, walk: walk, dog: dog)
        if walkDog.walk?.id != walk.id {
            walkDog.walk = walk
        }
        if walkDog.dog?.id != dog.id {
            walkDog.dog = dog
        }
        return walkDog
    }
}
