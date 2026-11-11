//
//  ServerCompletedRing.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// The ring stamp of a dog, on the server. The server keeps only the
/// earliest record of each dog, ring number and centre.
nonisolated struct ServerCompletedRing: ServerRow, Equatable {
    static let table = ServerTable.completedRings

    var id: UUID
    var packID: UUID
    var dogID: UUID
    /// The number of the ring, from 1.
    var ring: Int
    var radiusMetres: Double
    var centreLatitude: Double
    var centreLongitude: Double
    var completedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, ring
        case packID = "pack_id"
        case dogID = "dog_id"
        case radiusMetres = "radius_m"
        case centreLatitude = "centre_latitude"
        case centreLongitude = "centre_longitude"
        case completedAt = "completed_at"
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(packID, forKey: .packID)
        try container.encode(dogID, forKey: .dogID)
        try container.encode(ring, forKey: .ring)
        try container.encode(radiusMetres, forKey: .radiusMetres)
        try container.encode(centreLatitude, forKey: .centreLatitude)
        try container.encode(centreLongitude, forKey: .centreLongitude)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

/// A ring stamp finds its dog by its ID, like an area step.
extension ServerCompletedRing: SyncedRow {
    static var waitingRows: FetchDescriptor<CompletedRing> {
        FetchDescriptor(predicate: #Predicate<CompletedRing> { $0.isWaitingToUpload })
    }

    static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<CompletedRing> {
        FetchDescriptor(predicate: #Predicate<CompletedRing> {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        })
    }

    static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<CompletedRing> {
        FetchDescriptor(predicate: #Predicate<CompletedRing> { ids.contains($0.id) })
    }

    static func targets(of local: CompletedRing) -> [SyncedTarget]? {
        [.dog(local.dogID)]
    }

    var targets: [SyncedTarget] {
        [.dog(dogID)]
    }

    init(_ local: CompletedRing, packID: UUID, filePath: String?) {
        self.init(
            id: local.id, packID: packID, dogID: local.dogID, ring: local.number, radiusMetres: local.radiusMetres,
            centreLatitude: local.centreLatitude, centreLongitude: local.centreLongitude,
            completedAt: local.completedAt, deletedAt: local.deletedAt)
    }

    func store(in local: CompletedRing?, targets: StoreTargets) -> CompletedRing {
        let completedRing = local ?? CompletedRing(
            id: id, dogID: dogID, number: ring, radiusMetres: radiusMetres, centreLatitude: centreLatitude,
            centreLongitude: centreLongitude, completedAt: completedAt)
        completedRing.set(\.dogID, to: dogID)
        completedRing.set(\.number, to: ring)
        completedRing.set(\.radiusMetres, to: radiusMetres)
        completedRing.set(\.centreLatitude, to: centreLatitude)
        completedRing.set(\.centreLongitude, to: centreLongitude)
        completedRing.set(\.completedAt, to: completedAt)
        return completedRing
    }
}
