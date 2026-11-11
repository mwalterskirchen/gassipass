//
//  WalkMatchCache.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation

/// Keeps the match of each ended walk on disk, so that a rebuild matches
/// only the walks that it has not matched before. It is only a cache: the
/// collections can always be rebuilt from the tracks (ADR 0002). Each build
/// of the app and each set of map packages has its own folder
/// (`CacheFolder`), because new rules, a new package or a new map release
/// change the matches.
public nonisolated struct WalkMatchCache: Sendable {
    /// The walk that a match belongs to. A track does not change after its
    /// walk has ended, so the start, the end and the distance of the walk
    /// name its track.
    public struct Key: Hashable, Codable, Sendable {
        public let startedAt: Date
        public let endedAt: Date
        public let distanceMetres: Double

        fileprivate var fileName: String {
            [startedAt.timeIntervalSinceReferenceDate, endedAt.timeIntervalSinceReferenceDate, distanceMetres]
                .map { String($0.bitPattern, radix: 16) }
                .joined(separator: "-") + ".plist"
        }

        public init(startedAt: Date, endedAt: Date, distanceMetres: Double) {
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.distanceMetres = distanceMetres
        }
    }

    public let folder: URL

    /// The cache of this build of the app and the packages with the
    /// identity (`MapPackages.identity()`) in the root, or nil if its folder
    /// cannot be made. A walk is matched again when the package of its area
    /// arrives (ADR 0002), because the identity of the packages changes.
    public static func forPackages(_ identity: String, in root: URL) -> WalkMatchCache? {
        CacheFolder.folder(for: identity, in: root).map(WalkMatchCache.init(folder:))
    }

    /// The stored match of the walk, or nil if there is none or it cannot be read.
    public func match(for key: Key) -> WalkMatch? {
        guard let data = try? Data(contentsOf: folder.appending(path: key.fileName)) else { return nil }
        return try? PropertyListDecoder().decode(WalkMatch.self, from: data)
    }

    /// Stores the match of the walk. A match that cannot be stored is
    /// matched again by the next rebuild.
    public func store(_ match: WalkMatch, for key: Key) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(match) else { return }
        try? data.write(to: folder.appending(path: key.fileName), options: .atomic)
    }

    /// Removes the matches of all other walks, for example of deleted walks.
    public func removeAll(except keys: Set<Key>) {
        let kept = Set(keys.map(\.fileName))
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where !kept.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    public init(folder: URL) {
        self.folder = folder
    }
}

extension WalkMatchCache.Key {
    /// The key of an ended walk.
    public init?(_ walk: Walk) {
        guard let endedAt = walk.endedAt else { return nil }
        self.init(startedAt: walk.startedAt, endedAt: endedAt, distanceMetres: walk.distanceMetres)
    }
}
