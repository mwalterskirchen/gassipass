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
public nonisolated struct ServerWalk: ServerRow, Equatable {
    public static let table = ServerTable.walks

    public var id: UUID
    public var packID: UUID
    public var startedAt: Date
    public var endedAt: Date
    /// The path of the GPS track in Storage, or nil for a walk without a track.
    public var trackPath: String?
    public var distanceMetres: Double
    public var distanceVersion: Int
    public var continuedAt: Date?
    public var deviceID: String
    /// The name of the member who recorded the walk. The server gives an
    /// empty name the name of the pack owner.
    public var memberName: String
    public var deletedAt: Date?

    public enum CodingKeys: String, CodingKey {
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

    public func encode(to encoder: any Encoder) throws {
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

    public init(
        id: UUID,
        packID: UUID,
        startedAt: Date,
        endedAt: Date,
        trackPath: String? = nil,
        distanceMetres: Double,
        distanceVersion: Int,
        continuedAt: Date? = nil,
        deviceID: String,
        memberName: String,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.packID = packID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.trackPath = trackPath
        self.distanceMetres = distanceMetres
        self.distanceVersion = distanceVersion
        self.continuedAt = continuedAt
        self.deviceID = deviceID
        self.memberName = memberName
        self.deletedAt = deletedAt
    }
}

extension ServerWalk: SyncedRow {
    /// A walk that is still being recorded waits until it ends.
    public static var waitingRows: FetchDescriptor<Walk> {
        FetchDescriptor(predicate: #Predicate<Walk> { $0.isWaitingToUpload && $0.endedAt != nil })
    }

    public static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<Walk> {
        FetchDescriptor(predicate: #Predicate<Walk> {
            $0.isWaitingToUpload && $0.endedAt != nil && $0.changedAt > start && $0.changedAt <= end
        })
    }

    public static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<Walk> {
        FetchDescriptor(predicate: #Predicate<Walk> { ids.contains($0.id) })
    }

    public static func targets(of local: Walk) -> [SyncedTarget]? {
        []
    }

    public var targets: [SyncedTarget] {
        []
    }

    /// A walk is on the server only after it ends.
    public static func isOnServer(_ local: Walk) -> Bool {
        local.endedAt != nil && !local.isWaitingToUpload
    }

    /// The GPS track of an ended walk never changes, so it keeps its path. A
    /// walk is stored only with its GPS track, because the collection is
    /// calculated from it.
    public static var file: SyncedFile<ServerWalk>? {
        SyncedFile(
            bucket: .tracks, data: \.trackData, path: \.trackPath,
            newFile: { walk, pack, _ in .track(walk: walk, pack: pack) }, neverChanges: true,
            storesRowWithoutFile: false)
    }

    public init?(_ local: Walk, packID: UUID, filePath: String?) {
        guard let endedAt = local.endedAt else { return nil }
        self.init(
            id: local.id, packID: packID, startedAt: local.startedAt, endedAt: endedAt, trackPath: filePath,
            distanceMetres: local.distanceMetres, distanceVersion: local.distanceVersion,
            continuedAt: local.continuedAt, deviceID: local.deviceID, memberName: local.memberName,
            deletedAt: local.deletedAt)
    }

    public func store(in local: Walk?, targets: StoreTargets) -> Walk {
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
