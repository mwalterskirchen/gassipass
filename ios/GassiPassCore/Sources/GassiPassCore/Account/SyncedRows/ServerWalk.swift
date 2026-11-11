//
//  ServerWalk.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// An ended walk on the server. A walk that is still being recorded stays
/// on its phone until it ends.
nonisolated struct ServerWalk: ServerRow, Equatable {
    static let table = ServerTable.walks

    var id: UUID
    var packID: UUID
    var startedAt: Date
    var endedAt: Date
    /// The path of the GPS track in Storage, or nil for a walk without a track.
    var trackPath: String?
    var distanceMetres: Double
    var distanceVersion: Int
    var continuedAt: Date?
    var deviceID: String
    /// The name of the member who recorded the walk. The server gives an
    /// empty name the name of the pack owner.
    var memberName: String
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case packID = "pack_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case trackPath = "track_path"
        case distanceMetres = "distance_metres"
        case distanceVersion = "distance_version"
        case continuedAt = "continued_at"
        case deviceID = "device_id"
        case memberName = "member_name"
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(packID, forKey: .packID)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(trackPath, forKey: .trackPath)
        try container.encode(distanceMetres, forKey: .distanceMetres)
        try container.encode(distanceVersion, forKey: .distanceVersion)
        try container.encode(continuedAt, forKey: .continuedAt)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(memberName, forKey: .memberName)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

extension ServerWalk: SyncedRow {
    /// A walk that is still being recorded waits until it ends.
    static var waitingRows: FetchDescriptor<Walk> {
        FetchDescriptor(predicate: #Predicate<Walk> { $0.isWaitingToUpload && $0.endedAt != nil })
    }

    static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<Walk> {
        FetchDescriptor(predicate: #Predicate<Walk> {
            $0.isWaitingToUpload && $0.endedAt != nil && $0.changedAt > start && $0.changedAt <= end
        })
    }

    static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<Walk> {
        FetchDescriptor(predicate: #Predicate<Walk> { ids.contains($0.id) })
    }

    static func targets(of local: Walk) -> [SyncedTarget]? {
        []
    }

    var targets: [SyncedTarget] {
        []
    }

    /// A walk is on the server only after it ends.
    static func isOnServer(_ local: Walk) -> Bool {
        local.endedAt != nil && !local.isWaitingToUpload
    }

    /// The GPS track of an ended walk never changes, so it keeps its path. A
    /// walk is stored only with its GPS track, because the collection is
    /// calculated from it.
    static var file: SyncedFile<ServerWalk>? {
        SyncedFile(
            bucket: .tracks, data: \.trackData, path: \.trackPath,
            newFile: { walk, pack, _ in .track(walk: walk, pack: pack) }, neverChanges: true,
            storesRowWithoutFile: false)
    }

    init?(_ local: Walk, packID: UUID, filePath: String?) {
        guard let endedAt = local.endedAt else { return nil }
        self.init(
            id: local.id, packID: packID, startedAt: local.startedAt, endedAt: endedAt, trackPath: filePath,
            distanceMetres: local.distanceMetres, distanceVersion: local.distanceVersion,
            continuedAt: local.continuedAt, deviceID: local.deviceID, memberName: local.memberName,
            deletedAt: local.deletedAt)
    }

    func store(in local: Walk?, targets: StoreTargets) -> Walk {
        let walk = local ?? Walk(id: id, startedAt: startedAt)
        walk.set(\.startedAt, to: startedAt)
        walk.set(\.endedAt, to: endedAt)
        walk.set(\.distanceMetres, to: distanceMetres)
        walk.set(\.distanceVersion, to: distanceVersion)
        walk.set(\.continuedAt, to: continuedAt)
        walk.set(\.deviceID, to: deviceID)
        walk.set(\.memberName, to: memberName)
        return walk
    }
}
