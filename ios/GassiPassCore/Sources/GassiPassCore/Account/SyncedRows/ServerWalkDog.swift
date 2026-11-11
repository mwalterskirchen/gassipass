//
//  ServerWalkDog.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// One dog that takes part in one walk, on the server.
nonisolated struct ServerWalkDog: ServerRow, Equatable {
    static let table = ServerTable.walkDogs

    var id: UUID
    var packID: UUID
    var walkID: UUID
    var dogID: UUID
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case packID = "pack_id"
        case walkID = "walk_id"
        case dogID = "dog_id"
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(packID, forKey: .packID)
        try container.encode(walkID, forKey: .walkID)
        try container.encode(dogID, forKey: .dogID)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

extension ServerWalkDog: SyncedRow {
    static var waitingRows: FetchDescriptor<WalkDog> {
        FetchDescriptor(predicate: #Predicate<WalkDog> { $0.isWaitingToUpload })
    }

    /// A dog of a walk that is still being recorded does not count, because
    /// it uploads only after the walk ends.
    static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<WalkDog> {
        FetchDescriptor(predicate: #Predicate<WalkDog> {
            $0.isWaitingToUpload && $0.walk?.endedAt != nil && $0.changedAt > start && $0.changedAt <= end
        })
    }

    static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<WalkDog> {
        FetchDescriptor(predicate: #Predicate<WalkDog> { ids.contains($0.id) })
    }

    static func targets(of local: WalkDog) -> [SyncedTarget]? {
        guard let walk = local.walk, let dog = local.dog else { return nil }
        return [.walk(walk.id), .dog(dog.id)]
    }

    var targets: [SyncedTarget] {
        [.walk(walkID), .dog(dogID)]
    }

    init?(_ local: WalkDog, packID: UUID, filePath: String?) {
        guard let walk = local.walk, let dog = local.dog else { return nil }
        self.init(id: local.id, packID: packID, walkID: walk.id, dogID: dog.id, deletedAt: local.deletedAt)
    }

    func store(in local: WalkDog?, targets: StoreTargets) throws -> WalkDog {
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
