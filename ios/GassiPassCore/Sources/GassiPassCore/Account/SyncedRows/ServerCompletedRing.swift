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
public nonisolated struct ServerCompletedRing: ServerRow, Equatable {
    public static let table = ServerTable.completedRings

    public var id: UUID
    public var packID: UUID
    public var dogID: UUID
    /// The number of the ring, from 1.
    public var ring: Int
    public var radiusMetres: Double
    public var centreLatitude: Double
    public var centreLongitude: Double
    public var completedAt: Date
    public var deletedAt: Date?

    public enum CodingKeys: String, CodingKey {
        case id, ring
        case packID = "pack_id"
        case dogID = "dog_id"
        case radiusMetres = "radius_m"
        case centreLatitude = "centre_latitude"
        case centreLongitude = "centre_longitude"
        case completedAt = "completed_at"
        case deletedAt = "deleted_at"
    }

    public func encode(to encoder: any Encoder) throws {
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

    public init(
        id: UUID,
        packID: UUID,
        dogID: UUID,
        ring: Int,
        radiusMetres: Double,
        centreLatitude: Double,
        centreLongitude: Double,
        completedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.packID = packID
        self.dogID = dogID
        self.ring = ring
        self.radiusMetres = radiusMetres
        self.centreLatitude = centreLatitude
        self.centreLongitude = centreLongitude
        self.completedAt = completedAt
        self.deletedAt = deletedAt
    }
}

/// A ring stamp finds its dog by its ID, like an area step.
extension ServerCompletedRing: SyncedRow {
    public static var waitingRows: FetchDescriptor<CompletedRing> {
        FetchDescriptor(predicate: #Predicate<CompletedRing> { $0.isWaitingToUpload })
    }

    public static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<CompletedRing> {
        FetchDescriptor(predicate: #Predicate<CompletedRing> {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        })
    }

    public static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<CompletedRing> {
        FetchDescriptor(predicate: #Predicate<CompletedRing> { ids.contains($0.id) })
    }

    public static func targets(of local: CompletedRing) -> [SyncedTarget]? {
        [.dog(local.dogID)]
    }

    public var targets: [SyncedTarget] {
        [.dog(dogID)]
    }

    public init(_ local: CompletedRing, packID: UUID, filePath: String?) {
        self.init(
            id: local.id, packID: packID, dogID: local.dogID, ring: local.number, radiusMetres: local.radiusMetres,
            centreLatitude: local.centreLatitude, centreLongitude: local.centreLongitude,
            completedAt: local.completedAt, deletedAt: local.deletedAt)
    }

    public func store(in local: CompletedRing?, targets: StoreTargets) -> CompletedRing {
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
