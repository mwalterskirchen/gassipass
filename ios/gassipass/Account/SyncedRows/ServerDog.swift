//
//  ServerDog.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// A dog on the server.
nonisolated struct ServerDog: ServerRow, Equatable {
    static let table = ServerTable.dogs

    var id: UUID
    var packID: UUID
    var name: String
    /// The path of the photo in Storage, or nil for a dog without a photo.
    var photoPath: String?
    var retiredAt: Date?
    var retirementReason: String
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case packID = "pack_id"
        case photoPath = "photo_path"
        case retiredAt = "retired_at"
        case retirementReason = "retirement_reason"
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(packID, forKey: .packID)
        try container.encode(name, forKey: .name)
        try container.encode(photoPath, forKey: .photoPath)
        try container.encode(retiredAt, forKey: .retiredAt)
        try container.encode(retirementReason, forKey: .retirementReason)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

extension ServerDog: SyncedRow {
    static var waitingRows: FetchDescriptor<Dog> {
        FetchDescriptor(predicate: #Predicate<Dog> { $0.isWaitingToUpload })
    }

    static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<Dog> {
        FetchDescriptor(predicate: #Predicate<Dog> {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        })
    }

    static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<Dog> {
        FetchDescriptor(predicate: #Predicate<Dog> { ids.contains($0.id) })
    }

    static func targets(of local: Dog) -> [SyncedTarget]? {
        []
    }

    var targets: [SyncedTarget] {
        []
    }

    /// Each new photo gets a path of its own. A dog whose photo fails to
    /// download is stored without the new photo, so that its walks and
    /// records can point to it.
    static var file: SyncedFile<ServerDog>? {
        SyncedFile(
            bucket: .dogPhotos, data: \.photoData, path: \.photoPath,
            newFile: { .dogPhoto(dog: $0, pack: $1, hash: $2) }, neverChanges: false, storesRowWithoutFile: true)
    }

    init(_ local: Dog, packID: UUID, filePath: String?) {
        self.init(
            id: local.id, packID: packID, name: local.name, photoPath: filePath, retiredAt: local.retiredAt,
            retirementReason: local.retirementReason, deletedAt: local.deletedAt)
    }

    func store(in local: Dog?, targets: StoreTargets) -> Dog {
        let dog = local ?? Dog(id: id, name: name)
        dog.set(\.name, to: name)
        dog.set(\.retiredAt, to: retiredAt)
        dog.set(\.retirementReason, to: retirementReason)
        if dog.pack?.id != targets.pack.id {
            dog.pack = targets.pack
        }
        return dog
    }
}
