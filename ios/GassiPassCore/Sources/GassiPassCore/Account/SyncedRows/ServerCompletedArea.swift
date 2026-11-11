//
//  ServerCompletedArea.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// The record that a dog has completed an area, on the server. The server
/// keeps only the earliest record of each dog and area.
public nonisolated struct ServerCompletedArea: ServerRow, Equatable {
    public static let table = ServerTable.completedAreas

    public var id: UUID
    public var packID: UUID
    public var dogID: UUID
    /// The BFS number of the area.
    public var area: Int
    public var completedAt: Date
    public var deletedAt: Date?

    public enum CodingKeys: String, CodingKey {
        case id, area
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
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    public init(id: UUID, packID: UUID, dogID: UUID, area: Int, completedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.packID = packID
        self.dogID = dogID
        self.area = area
        self.completedAt = completedAt
        self.deletedAt = deletedAt
    }
}

extension ServerCompletedArea: SyncedRow {
    public static var waitingRows: FetchDescriptor<CompletedArea> {
        FetchDescriptor(predicate: #Predicate<CompletedArea> { $0.isWaitingToUpload })
    }

    public static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<CompletedArea> {
        FetchDescriptor(predicate: #Predicate<CompletedArea> {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        })
    }

    public static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<CompletedArea> {
        FetchDescriptor(predicate: #Predicate<CompletedArea> { ids.contains($0.id) })
    }

    public static func targets(of local: CompletedArea) -> [SyncedTarget]? {
        local.dog.map { [.dog($0.id)] }
    }

    public var targets: [SyncedTarget] {
        [.dog(dogID)]
    }

    public init?(_ local: CompletedArea, packID: UUID, filePath: String?) {
        guard let dog = local.dog else { return nil }
        self.init(
            id: local.id, packID: packID, dogID: dog.id, area: local.area, completedAt: local.completedAt,
            deletedAt: local.deletedAt)
    }

    public func store(in local: CompletedArea?, targets: StoreTargets) throws -> CompletedArea {
        let dog = try targets.local(ServerDog.self, dogID)
        let record = local ?? CompletedArea(id: id, dog: dog, area: area, completedAt: completedAt)
        if record.dog?.id != dog.id {
            record.dog = dog
        }
        record.set(\.area, to: area)
        record.set(\.completedAt, to: completedAt)
        return record
    }
}
