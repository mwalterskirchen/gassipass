//
//  ServerDog.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// A dog on the server.
public nonisolated struct ServerDog: ServerRow, Equatable {
    public static let table = ServerTable.dogs

    public var id: UUID
    public var packID: UUID
    public var name: String
    /// The path of the photo in Storage, or nil for a dog without a photo.
    public var photoPath: String?
    public var retiredAt: Date?
    public var retirementReason: String
    /// The date of birth. The server keeps it as a day (`WeekCalendar.dayText(of:)`).
    public var bornOn: Date? = nil
    /// The issue date of the passport. A phone from before the issue dates
    /// uploads a dog without it, and the server gives the dog the time of the
    /// upload.
    public var addedAt: Date? = nil
    public var deletedAt: Date?

    public enum CodingKeys: String, CodingKey {
        case id, name
        case packID = "pack_id"
        case photoPath = "photo_path"
        case retiredAt = "retired_at"
        case retirementReason = "retirement_reason"
        case bornOn = "born_on"
        case addedAt = "added_at"
        case deletedAt = "deleted_at"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(packID, forKey: .packID)
        try container.encode(name, forKey: .name)
        try container.encode(photoPath, forKey: .photoPath)
        try container.encode(retiredAt, forKey: .retiredAt)
        try container.encode(retirementReason, forKey: .retirementReason)
        try container.encode(bornOn.map(WeekCalendar.dayText(of:)), forKey: .bornOn)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    public init(
        id: UUID,
        packID: UUID,
        name: String,
        photoPath: String? = nil,
        retiredAt: Date? = nil,
        retirementReason: String,
        bornOn: Date? = nil,
        addedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.packID = packID
        self.name = name
        self.photoPath = photoPath
        self.retiredAt = retiredAt
        self.retirementReason = retirementReason
        self.bornOn = bornOn
        self.addedAt = addedAt
        self.deletedAt = deletedAt
    }
}

extension ServerDog {
    // In an extension, so that the struct keeps its memberwise initializer.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        packID = try container.decode(UUID.self, forKey: .packID)
        name = try container.decode(String.self, forKey: .name)
        photoPath = try container.decodeIfPresent(String.self, forKey: .photoPath)
        retiredAt = try container.decodeIfPresent(Date.self, forKey: .retiredAt)
        retirementReason = try container.decode(String.self, forKey: .retirementReason)
        bornOn = try container.decodeDayIfPresent(forKey: .bornOn)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

extension ServerDog: SyncedRow {
    public static var waitingRows: FetchDescriptor<Dog> {
        FetchDescriptor(predicate: #Predicate<Dog> { $0.isWaitingToUpload })
    }

    public static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<Dog> {
        FetchDescriptor(predicate: #Predicate<Dog> {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        })
    }

    public static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<Dog> {
        FetchDescriptor(predicate: #Predicate<Dog> { ids.contains($0.id) })
    }

    public static func targets(of local: Dog) -> [SyncedTarget]? {
        []
    }

    public var targets: [SyncedTarget] {
        []
    }

    /// Each new photo gets a path of its own. A dog whose photo fails to
    /// download is stored without the new photo, so that its walks and
    /// records can point to it.
    public static var file: SyncedFile<ServerDog>? {
        SyncedFile(
            bucket: .dogPhotos, data: \.photoData, path: \.photoPath,
            newFile: { .dogPhoto(dog: $0, pack: $1, hash: $2) }, neverChanges: false, storesRowWithoutFile: true)
    }

    public init(_ local: Dog, packID: UUID, filePath: String?) {
        self.init(
            id: local.id, packID: packID, name: local.name, photoPath: filePath, retiredAt: local.retiredAt,
            retirementReason: local.retirementReason, bornOn: local.bornOn, addedAt: local.addedAt,
            deletedAt: local.deletedAt)
    }

    public func store(in local: Dog?, targets: StoreTargets) -> Dog {
        let dog = local ?? Dog(id: id, name: name)
        dog.set(\.name, to: name)
        dog.set(\.retiredAt, to: retiredAt)
        dog.set(\.retirementReason, to: retirementReason)
        dog.set(\.bornOn, to: bornOn)
        dog.set(\.addedAt, to: addedAt)
        if dog.pack?.id != targets.pack.id {
            dog.pack = targets.pack
        }
        return dog
    }
}
