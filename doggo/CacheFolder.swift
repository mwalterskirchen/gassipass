//
//  CacheFolder.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation

/// A folder in the caches folder of the app, for data that the app can make
/// again, for example the matches of walks or the images of areas. The
/// system can empty it at any time.
///
/// Each version of the data has its own folder in the folder of its kind.
/// The version names the build of the app and the map release, because a
/// new build or a new map release changes the data. Making the folder of a
/// version removes the folders of the other versions.
nonisolated enum CacheFolder {
    /// The folder of the kind and the map release in the caches folder of
    /// the app, or nil if it cannot be made.
    static func folder(of kind: String, mapRelease: String) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return make(version: "\(appBuild) \(mapRelease)", in: caches.appending(path: kind, directoryHint: .isDirectory))
    }

    /// Makes the folder of the version in the root, and removes the folders
    /// of the other versions. It returns nil if the folder cannot be made.
    static func make(version: String, in root: URL) -> URL? {
        let folder = root.appending(path: version, directoryHint: .isDirectory)
        let others = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for other in others where other.standardizedFileURL != folder.standardizedFileURL {
            try? FileManager.default.removeItem(at: other)
        }
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
        else { return nil }
        return folder
    }

    /// The map release of the bundled packages, or nil if they cannot open.
    static func bundledMapRelease() -> String? {
        guard let packages = try? MapPackage.bundled() else { return nil }
        return Set(packages.map(\.mapRelease)).sorted().joined(separator: "+")
    }

    /// The build of the app: its version and the time of the build, so that
    /// every new build during development also starts new caches.
    private static var appBuild: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let built = Bundle.main.executableURL
            .flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        return "\(version) \(Int(built?.timeIntervalSinceReferenceDate ?? 0))"
    }
}
