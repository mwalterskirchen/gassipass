//
//  ServerAreaStep.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// The record that a dog has reached a step of the stamp of an area, on the
/// server. The server keeps only the earliest record of each dog, area and
/// step.
nonisolated struct ServerAreaStep: ServerRow, Equatable {
    static let table = ServerTable.areaSteps

    var id: UUID
    var packID: UUID
    var dogID: UUID
    /// The BFS number of the area.
    var area: Int
    /// The step (`StampStep.rawValue`): 0 for the entry stamp, or 25, 50 or 75.
    var step: Int
    var reachedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, area, step
        case packID = "pack_id"
        case dogID = "dog_id"
        case reachedAt = "reached_at"
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(packID, forKey: .packID)
        try container.encode(dogID, forKey: .dogID)
        try container.encode(area, forKey: .area)
        try container.encode(step, forKey: .step)
        try container.encode(reachedAt, forKey: .reachedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

/// An area step keeps the ID of its dog and no relationship
/// (`LocalSchemaV3`), so it finds its dog by the ID.
extension ServerAreaStep: SyncedRow {
    static var waitingRows: FetchDescriptor<AreaStep> {
        FetchDescriptor(predicate: #Predicate<AreaStep> { $0.isWaitingToUpload })
    }

    static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<AreaStep> {
        FetchDescriptor(predicate: #Predicate<AreaStep> {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        })
    }

    static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<AreaStep> {
        FetchDescriptor(predicate: #Predicate<AreaStep> { ids.contains($0.id) })
    }

    static func targets(of local: AreaStep) -> [SyncedTarget]? {
        [.dog(local.dogID)]
    }

    var targets: [SyncedTarget] {
        [.dog(dogID)]
    }

    init(_ local: AreaStep, packID: UUID, filePath: String?) {
        self.init(
            id: local.id, packID: packID, dogID: local.dogID, area: local.area, step: local.step,
            reachedAt: local.reachedAt, deletedAt: local.deletedAt)
    }

    func store(in local: AreaStep?, targets: StoreTargets) -> AreaStep {
        let areaStep = local ?? AreaStep(id: id, dogID: dogID, area: area, step: step, reachedAt: reachedAt)
        areaStep.set(\.dogID, to: dogID)
        areaStep.set(\.area, to: area)
        areaStep.set(\.step, to: step)
        areaStep.set(\.reachedAt, to: reachedAt)
        return areaStep
    }
}
