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
    /// The date of birth. The server keeps it as a day (`WeekCalendar.dayText(of:)`).
    var bornOn: Date? = nil
    /// The issue date of the passport. A phone from before the issue dates
    /// uploads a dog without it, and the server gives the dog the time of the
    /// upload.
    var addedAt: Date? = nil
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case packID = "pack_id"
        case photoPath = "photo_path"
        case retiredAt = "retired_at"
        case retirementReason = "retirement_reason"
        case bornOn = "born_on"
        case addedAt = "added_at"
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
        try container.encode(bornOn.map(WeekCalendar.dayText(of:)), forKey: .bornOn)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

extension ServerDog {
    // In an extension, so that the struct keeps its memberwise initializer.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        packID = try container.decode(UUID.self, forKey: .packID)
        name = try container.decode(String.self, forKey: .name)
        photoPath = try container.decodeIfPresent(String.self, forKey: .photoPath)
        retiredAt = try container.decodeIfPresent(Date.self, forKey: .retiredAt)
        retirementReason = try container.decode(String.self, forKey: .retirementReason)
        if let day = try container.decodeIfPresent(String.self, forKey: .bornOn) {
            guard let bornOn = WeekCalendar.date(ofDayText: day) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .bornOn, in: container, debugDescription: "The date of birth is no day: \(day)")
            }
            self.bornOn = bornOn
        }
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
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
            retirementReason: local.retirementReason, bornOn: local.bornOn, addedAt: local.addedAt,
            deletedAt: local.deletedAt)
    }

    func store(in local: Dog?, targets: StoreTargets) -> Dog {
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
