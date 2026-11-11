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
public nonisolated struct ServerAreaStep: ServerRow, Equatable {
    public static let table = ServerTable.areaSteps

    public var id: UUID
    public var packID: UUID
    public var dogID: UUID
    /// The BFS number of the area.
    public var area: Int
    /// The step (`StampStep.rawValue`): 0 for the entry stamp, or 25, 50 or 75.
    public var step: Int
    public var reachedAt: Date
    public var deletedAt: Date?

    public enum CodingKeys: String, CodingKey {
        case id, area, step
        case packID = "pack_id"
        case dogID = "dog_id"
        case reachedAt = "reached_at"
        case deletedAt = "deleted_at"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(packID, forKey: .packID)
        try container.encode(dogID, forKey: .dogID)
        try container.encode(area, forKey: .area)
        try container.encode(step, forKey: .step)
        try container.encode(reachedAt, forKey: .reachedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    public init(id: UUID, packID: UUID, dogID: UUID, area: Int, step: Int, reachedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.packID = packID
        self.dogID = dogID
        self.area = area
        self.step = step
        self.reachedAt = reachedAt
        self.deletedAt = deletedAt
    }
}

/// An area step keeps the ID of its dog and no relationship
/// (`LocalSchemaV3`), so it finds its dog by the ID.
extension ServerAreaStep: SyncedRow {
    public static var waitingRows: FetchDescriptor<AreaStep> {
        FetchDescriptor(predicate: #Predicate<AreaStep> { $0.isWaitingToUpload })
    }

    public static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<AreaStep> {
        FetchDescriptor(predicate: #Predicate<AreaStep> {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        })
    }

    public static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<AreaStep> {
        FetchDescriptor(predicate: #Predicate<AreaStep> { ids.contains($0.id) })
    }

    public static func targets(of local: AreaStep) -> [SyncedTarget]? {
        [.dog(local.dogID)]
    }

    public var targets: [SyncedTarget] {
        [.dog(dogID)]
    }

    public init(_ local: AreaStep, packID: UUID, filePath: String?) {
        self.init(
            id: local.id, packID: packID, dogID: local.dogID, area: local.area, step: local.step,
            reachedAt: local.reachedAt, deletedAt: local.deletedAt)
    }

    public func store(in local: AreaStep?, targets: StoreTargets) -> AreaStep {
        let areaStep = local ?? AreaStep(id: id, dogID: dogID, area: area, step: step, reachedAt: reachedAt)
        areaStep.set(\.dogID, to: dogID)
        areaStep.set(\.area, to: area)
        areaStep.set(\.step, to: step)
        areaStep.set(\.reachedAt, to: reachedAt)
        return areaStep
    }
}
