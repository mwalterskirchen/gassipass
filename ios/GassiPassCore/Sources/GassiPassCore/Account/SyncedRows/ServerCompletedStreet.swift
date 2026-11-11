//
//  ServerCompletedStreet.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// The record that a dog has completed a street, on the server. The server
/// keeps only the earliest record of each dog and street.
public nonisolated struct ServerCompletedStreet: ServerRow, Equatable {
    public static let table = ServerTable.completedStreets

    public var id: UUID
    public var packID: UUID
    public var dogID: UUID
    /// The BFS number of the area of the street.
    public var area: Int
    /// The official name of the street.
    public var street: String
    public var completedAt: Date
    public var deletedAt: Date?

    public enum CodingKeys: String, CodingKey {
        case id, area, street
        case packID = "pack_id"
        case dogID = "dog_id"
        case completedAt = "completed_at"
        case deletedAt = "deleted_at"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(packID, forKey: .packID)
        try container.encode(dogID, forKey: .dogID)
        try container.encode(area, forKey: .area)
        try container.encode(street, forKey: .street)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    public init(
        id: UUID,
        packID: UUID,
        dogID: UUID,
        area: Int,
        street: String,
        completedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.packID = packID
        self.dogID = dogID
        self.area = area
        self.street = street
        self.completedAt = completedAt
        self.deletedAt = deletedAt
    }
}

extension ServerCompletedStreet: SyncedRow {
    public static var waitingRows: FetchDescriptor<CompletedStreet> {
        FetchDescriptor(predicate: #Predicate<CompletedStreet> { $0.isWaitingToUpload })
    }

    public static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<CompletedStreet> {
        FetchDescriptor(predicate: #Predicate<CompletedStreet> {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        })
    }

    public static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<CompletedStreet> {
        FetchDescriptor(predicate: #Predicate<CompletedStreet> { ids.contains($0.id) })
    }

    public static func targets(of local: CompletedStreet) -> [SyncedTarget]? {
        local.dog.map { [.dog($0.id)] }
    }

    public var targets: [SyncedTarget] {
        [.dog(dogID)]
    }

    public init?(_ local: CompletedStreet, packID: UUID, filePath: String?) {
        guard let dog = local.dog else { return nil }
        self.init(
            id: local.id, packID: packID, dogID: dog.id, area: local.area, street: local.street,
            completedAt: local.completedAt, deletedAt: local.deletedAt)
    }

    public func store(in local: CompletedStreet?, targets: StoreTargets) throws -> CompletedStreet {
        let dog = try targets.local(ServerDog.self, dogID)
        let record = local ?? CompletedStreet(
            id: id, dog: dog, street: Street.ID(area: area, name: street), completedAt: completedAt)
        if record.dog?.id != dog.id {
            record.dog = dog
        }
        record.set(\.area, to: area)
        record.set(\.street, to: street)
        record.set(\.completedAt, to: completedAt)
        return record
    }
}
