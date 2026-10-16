//
//  ServerRows.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Foundation

/// The rows of the pack on the server (ADR 0006), as the phone uploads and
/// downloads them. The tables are in `supabase/migrations/`.
///
/// An upload writes the whole row, so each row encodes every column, also a
/// column without a value. A missing column would keep its old value on the
/// server, for example the deletion time of a dog that came back to a walk.

/// The pack on the server, as the phone downloads it.
nonisolated struct ServerPack: Decodable, Equatable, Sendable {
    var id: UUID
    /// The name that a member gave the pack, or empty for the default name.
    var name: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
    }
}

/// A table of the pack on the server, whose rows upload and download.
nonisolated enum ServerTable: String {
    case dogs, walks
    case walkDogs = "walk_dogs"
    case completedAreas = "completed_areas"
    case completedStreets = "completed_streets"
    case areaSteps = "area_steps"
}

/// A row of the pack that uploads and downloads.
nonisolated protocol ServerRow: Codable, Sendable {
    /// The table of the row.
    static var table: ServerTable { get }
    /// The stable ID of the row, which is the same on every phone.
    var id: UUID { get }
    var packID: UUID { get }
}

/// A downloaded row, with the time of its last change on the server. The
/// next download asks for the rows that changed since.
nonisolated struct Downloaded<Row: Decodable & Sendable>: Decodable, Sendable {
    var row: Row
    var changedAt: Date

    private enum CodingKeys: String, CodingKey {
        case changedAt = "changed_at"
    }

    init(row: Row, changedAt: Date) {
        self.row = row
        self.changedAt = changedAt
    }

    init(from decoder: any Decoder) throws {
        row = try Row(from: decoder)
        changedAt = try decoder.container(keyedBy: CodingKeys.self).decode(Date.self, forKey: .changedAt)
    }
}

extension Downloaded: Equatable where Row: Equatable {}

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
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case packID = "pack_id"
        case photoPath = "photo_path"
        case retiredAt = "retired_at"
        case retirementReason = "retirement_reason"
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
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

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

/// One dog that takes part in one walk, on the server.
nonisolated struct ServerWalkDog: ServerRow, Equatable {
    static let table = ServerTable.walkDogs

    var id: UUID
    var packID: UUID
    var walkID: UUID
    var dogID: UUID
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case packID = "pack_id"
        case walkID = "walk_id"
        case dogID = "dog_id"
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(packID, forKey: .packID)
        try container.encode(walkID, forKey: .walkID)
        try container.encode(dogID, forKey: .dogID)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

/// The record that a dog has completed an area, on the server. The server
/// keeps only the earliest record of each dog and area.
nonisolated struct ServerCompletedArea: ServerRow, Equatable {
    static let table = ServerTable.completedAreas

    var id: UUID
    var packID: UUID
    var dogID: UUID
    /// The BFS number of the area.
    var area: Int
    var completedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, area
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
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

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

/// A file of the pack in Storage: a GPS track or a photo of a dog. Each pack
/// has a folder with its ID in each bucket, and row-level security lets only
/// the members of the pack into it. The files of a pack that moved into
/// another pack stay in the folder of the old pack, where the members of the
/// new pack read them.
///
/// A row points to its file with the path. The phone notes the path of the
/// file of each row (`UploadedFiles`), so that it finds the file also in the
/// folder of a pack that moved.
nonisolated struct ServerFile: Hashable, Sendable {
    enum Bucket: String, CaseIterable, Sendable {
        case tracks
        case dogPhotos = "dog-photos"
    }

    var bucket: Bucket
    /// The path in the bucket. The first folder is the ID of the pack.
    var path: String

    /// The GPS track of a walk, encoded by `Track`. The track of an ended
    /// walk never changes, so it keeps its path.
    static func track(walk: UUID, pack: UUID) -> ServerFile {
        ServerFile(bucket: .tracks, path: "\(folder(of: pack))/\(text(walk))")
    }

    /// A photo of a dog, a JPEG made by `DogPhoto`. Each new photo gets a
    /// path of its own from the hash of its content, so that a phone
    /// downloads a photo only when it is new.
    static func dogPhoto(dog: UUID, pack: UUID, hash: String) -> ServerFile {
        ServerFile(bucket: .dogPhotos, path: "\(folder(of: pack))/\(text(dog))-\(hash.prefix(16)).jpg")
    }

    var contentType: String {
        switch bucket {
        case .tracks: "application/octet-stream"
        case .dogPhotos: "image/jpeg"
        }
    }

    /// The folder of the pack in each bucket. Postgres writes a UUID in
    /// lowercase, and the folder must match the pack ID that row-level
    /// security compares.
    static func folder(of pack: UUID) -> String {
        text(pack)
    }

    private static func text(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}
