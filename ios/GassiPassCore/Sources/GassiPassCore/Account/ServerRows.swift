//
//  ServerRows.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Foundation

/// The rows of the pack on the server (ADR 0006), as the phone uploads and
/// downloads them. The tables are in `supabase/migrations/`, and the row of
/// each synced table is in `SyncedRows/`.
///
/// An upload writes the whole row, so each row encodes every column, also a
/// column without a value. A missing column would keep its old value on the
/// server, for example the deletion time of a dog that came back to a walk.

/// The pack on the server, as the phone downloads it.
public nonisolated struct ServerPack: Decodable, Equatable, Sendable {
    public var id: UUID
    /// The name that a member gave the pack, or empty for the default name.
    public var name: String
    public var createdAt: Date
    /// The home base, or nil until a member sets it. Both coordinates have
    /// a value, or neither.
    public var homeLatitude: Double? = nil
    public var homeLongitude: Double? = nil
    public var homeSetAt: Date? = nil

    public enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case homeLatitude = "home_latitude"
        case homeLongitude = "home_longitude"
        case homeSetAt = "home_set_at"
    }

    /// The home base on the server, or nil.
    public var homeBase: HomeBase? {
        guard let homeLatitude, let homeLongitude else { return nil }
        return HomeBase(latitude: homeLatitude, longitude: homeLongitude)
    }

    public init(
        id: UUID,
        name: String,
        createdAt: Date,
        homeLatitude: Double? = nil,
        homeLongitude: Double? = nil,
        homeSetAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.homeLatitude = homeLatitude
        self.homeLongitude = homeLongitude
        self.homeSetAt = homeSetAt
    }
}

/// A change of the pack that a member uploads: its name, and its home base
/// when a member moved it on the phone. A change without a home base keeps
/// the home base on the server. Otherwise the last write wins (ADR 0006).
public nonisolated struct ServerPackChange: Encodable, Equatable, Sendable {
    public var name: String
    public var homeLatitude: Double?
    public var homeLongitude: Double?
    public var homeSetAt: Date?

    public enum CodingKeys: String, CodingKey {
        case name
        case homeLatitude = "home_latitude"
        case homeLongitude = "home_longitude"
        case homeSetAt = "home_set_at"
    }

    /// The home base of the change, or nil for a change of the name only.
    public var homeBase: HomeBase? {
        guard let homeLatitude, let homeLongitude else { return nil }
        return HomeBase(latitude: homeLatitude, longitude: homeLongitude)
    }

    public init(name: String, homeLatitude: Double? = nil, homeLongitude: Double? = nil, homeSetAt: Date? = nil) {
        self.name = name
        self.homeLatitude = homeLatitude
        self.homeLongitude = homeLongitude
        self.homeSetAt = homeSetAt
    }
}

/// A table of the pack on the server, whose rows upload and download.
public nonisolated enum ServerTable: String, Sendable {
    case dogs, walks
    case walkDogs = "walk_dogs"
    case completedAreas = "completed_areas"
    case completedStreets = "completed_streets"
    case areaSteps = "area_steps"
    case completedRings = "completed_rings"
    case weeklyGoals = "weekly_goals"
}

/// A row of the pack that uploads and downloads.
public nonisolated protocol ServerRow: Codable, Sendable {
    /// The table of the row.
    static var table: ServerTable { get }
    /// The stable ID of the row, which is the same on every phone.
    var id: UUID { get }
    var packID: UUID { get set }
}

nonisolated extension KeyedDecodingContainer {
    /// The day of a `date` column, as the midnight in Zurich at its start
    /// (`WeekCalendar.date(ofDayText:)`).
    func decodeDay(forKey key: Key) throws -> Date {
        let text = try decode(String.self, forKey: key)
        guard let day = WeekCalendar.date(ofDayText: text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "No day: \(text)")
        }
        return day
    }

    func decodeDayIfPresent(forKey key: Key) throws -> Date? {
        try contains(key) && !decodeNil(forKey: key) ? decodeDay(forKey: key) : nil
    }
}

/// A downloaded row, with the time of its last change on the server. The
/// next download asks for the rows that changed since.
public nonisolated struct Downloaded<Row: Decodable & Sendable>: Decodable, Sendable {
    public var row: Row
    public var changedAt: Date

    private enum CodingKeys: String, CodingKey {
        case changedAt = "changed_at"
    }

    public init(row: Row, changedAt: Date) {
        self.row = row
        self.changedAt = changedAt
    }

    public init(from decoder: any Decoder) throws {
        row = try Row(from: decoder)
        changedAt = try decoder.container(keyedBy: CodingKeys.self).decode(Date.self, forKey: .changedAt)
    }
}

extension Downloaded: Equatable where Row: Equatable {}

/// A file of the pack in Storage: a GPS track or a photo of a dog. Each pack
/// has a folder with its ID in each bucket, and row-level security lets only
/// the members of the pack into it. The files of a pack that moved into
/// another pack stay in the folder of the old pack, where the members of the
/// new pack read them.
///
/// A row points to its file with the path. The phone notes the path of the
/// file of each row (`UploadedFiles`), so that it finds the file also in the
/// folder of a pack that moved.
public nonisolated struct ServerFile: Hashable, Sendable {
    public enum Bucket: String, CaseIterable, Sendable {
        case tracks
        case dogPhotos = "dog-photos"
    }

    public var bucket: Bucket
    /// The path in the bucket. The first folder is the ID of the pack.
    public var path: String

    /// The GPS track of a walk, encoded by `Track`. The track of an ended
    /// walk never changes, so it keeps its path.
    public static func track(walk: UUID, pack: UUID) -> ServerFile {
        ServerFile(bucket: .tracks, path: "\(folder(of: pack))/\(text(walk))")
    }

    /// A photo of a dog, a JPEG made by `DogPhoto`. Each new photo gets a
    /// path of its own from the hash of its content, so that a phone
    /// downloads a photo only when it is new.
    public static func dogPhoto(dog: UUID, pack: UUID, hash: String) -> ServerFile {
        ServerFile(bucket: .dogPhotos, path: "\(folder(of: pack))/\(text(dog))-\(hash.prefix(16)).jpg")
    }

    public var contentType: String {
        switch bucket {
        case .tracks: "application/octet-stream"
        case .dogPhotos: "image/jpeg"
        }
    }

    /// The folder of the pack in each bucket. Postgres writes a UUID in
    /// lowercase, and the folder must match the pack ID that row-level
    /// security compares.
    public static func folder(of pack: UUID) -> String {
        text(pack)
    }

    private static func text(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    public init(bucket: Bucket, path: String) {
        self.bucket = bucket
        self.path = path
    }
}
