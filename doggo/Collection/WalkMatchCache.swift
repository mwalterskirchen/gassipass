//
//  WalkMatchCache.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation

/// Keeps the match of each ended walk on disk, so that a rebuild matches
/// only the walks that it has not matched before. It is only a cache: the
/// collections can always be rebuilt from the tracks (ADR 0002), and the
/// system can empty the caches folder at any time.
///
/// Each build of the app and each map release has its own folder, because
/// new rules or a new map release change the matches. The cache removes the
/// folders of other builds and releases.
nonisolated struct WalkMatchCache: Sendable {
    /// The walk that a match belongs to. A track does not change after its
    /// walk has ended, so the start, the end and the distance of the walk
    /// name its track.
    struct Key: Hashable, Sendable {
        let startedAt: Date
        let endedAt: Date
        let distanceMetres: Double

        fileprivate var fileName: String {
            [startedAt.timeIntervalSinceReferenceDate, endedAt.timeIntervalSinceReferenceDate, distanceMetres]
                .map { String($0.bitPattern, radix: 16) }
                .joined(separator: "-") + ".plist"
        }
    }

    let folder: URL

    /// The cache of this build of the app and the map release, in the caches
    /// folder of the app, or nil if the folder cannot be made.
    static func forApp(mapRelease: String) -> WalkMatchCache? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let root = caches.appending(path: "WalkMatches", directoryHint: .isDirectory)
        let cache = WalkMatchCache(root: root, build: appBuild, mapRelease: mapRelease)
        return cache.makeFolder(removingOthersIn: root) ? cache : nil
    }

    /// A cache in a folder of its own under the root, for a build and a map release.
    init(root: URL, build: String, mapRelease: String) {
        folder = root.appending(path: "\(build) \(mapRelease)", directoryHint: .isDirectory)
    }

    /// The stored match of the walk, or nil if there is none or it cannot be read.
    func match(for key: Key) -> WalkMatch? {
        guard let data = try? Data(contentsOf: folder.appending(path: key.fileName)) else { return nil }
        return try? PropertyListDecoder().decode(WalkMatch.self, from: data)
    }

    /// Stores the match of the walk. A match that cannot be stored is
    /// matched again by the next rebuild.
    func store(_ match: WalkMatch, for key: Key) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(match) else { return }
        try? data.write(to: folder.appending(path: key.fileName), options: .atomic)
    }

    /// Removes the matches of all other walks, for example of deleted walks.
    func removeAll(except keys: Set<Key>) {
        let kept = Set(keys.map(\.fileName))
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where !kept.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Makes the folder of this cache, and removes the other folders in the root.
    func makeFolder(removingOthersIn root: URL) -> Bool {
        let others = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for other in others where other.standardizedFileURL != folder.standardizedFileURL {
            try? FileManager.default.removeItem(at: other)
        }
        return (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
    }

    /// The build of the app: its version and the time of the build, so that
    /// every new build during development also starts a new cache.
    private static var appBuild: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let built = Bundle.main.executableURL
            .flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        return "\(version) \(Int(built?.timeIntervalSinceReferenceDate ?? 0))"
    }
}

extension WalkMatchCache.Key {
    /// The key of an ended walk.
    init?(_ walk: Walk) {
        guard let endedAt = walk.endedAt else { return nil }
        self.init(startedAt: walk.startedAt, endedAt: endedAt, distanceMetres: walk.distanceMetres)
    }
}
