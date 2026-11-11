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
nonisolated struct ServerCompletedStreet: ServerRow, Equatable {
    static let table = ServerTable.completedStreets

    var id: UUID
    var packID: UUID
    var dogID: UUID
    /// The BFS number of the area of the street.
    var area: Int
    /// The official name of the street.
    var street: String
    var completedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, area, street
        case packID = "pack_id"
        case dogID = "dog_id"
        case completedAt = "completed_at"
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(packID, forKey: .packID)
        try container.encode(dogID, forKey: .dogID)
        try container.encode(area, forKey: .area)
        try container.encode(street, forKey: .street)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

extension ServerCompletedStreet: SyncedRow {
    static var waitingRows: FetchDescriptor<CompletedStreet> {
        FetchDescriptor(predicate: #Predicate<CompletedStreet> { $0.isWaitingToUpload })
    }

    static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<CompletedStreet> {
        FetchDescriptor(predicate: #Predicate<CompletedStreet> {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        })
    }

    static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<CompletedStreet> {
        FetchDescriptor(predicate: #Predicate<CompletedStreet> { ids.contains($0.id) })
    }

    static func targets(of local: CompletedStreet) -> [SyncedTarget]? {
        local.dog.map { [.dog($0.id)] }
    }

    var targets: [SyncedTarget] {
        [.dog(dogID)]
    }

    init?(_ local: CompletedStreet, packID: UUID, filePath: String?) {
        guard let dog = local.dog else { return nil }
        self.init(
            id: local.id, packID: packID, dogID: dog.id, area: local.area, street: local.street,
            completedAt: local.completedAt, deletedAt: local.deletedAt)
    }

    func store(in local: CompletedStreet?, targets: StoreTargets) throws -> CompletedStreet {
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
