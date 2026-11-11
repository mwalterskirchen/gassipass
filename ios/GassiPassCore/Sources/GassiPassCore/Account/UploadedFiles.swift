//
//  UploadedFiles.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import CryptoKit
import Foundation

/// The file of each row on the server, as this phone last uploaded or
/// downloaded it: its path and a hash of its content. A row that changes
/// uploads again, but its photo or GPS track uploads again only when the file
/// has changed. A row that loses its file, or gets a new one, deletes the old
/// file at its path, also in the folder of a pack that moved. The user
/// defaults keep the list, so it survives a restart of the app.
final class UploadedFiles {
    /// A file on the server.
    struct File: Equatable {
        var path: String
        /// The SHA-256 hash of the content, in hex digits, or empty when
        /// Storage has no file at the path (`FileMissing`).
        var hash: String
    }

    private let defaults: UserDefaults
    /// The file of each row, by its bucket and the ID of the row.
    private var files: [String: File]

    private static let key = "uploadedFilesByRow"
    /// The key of the list before #127, which kept the hash of each file by
    /// its bucket and path.
    private static let keyByPath = "uploadedFiles"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.key) as? [String: [String: String]] ?? [:]
        files = stored.compactMapValues { file in
            guard let path = file["path"], let hash = file["hash"] else { return nil }
            return File(path: path, hash: hash)
        }
        if let hashesByPath = defaults.dictionary(forKey: Self.keyByPath) as? [String: String] {
            convert(hashesByPath)
        }
    }

    /// The file of the row on the server, or nil.
    func file(of row: UUID, in bucket: ServerFile.Bucket) -> File? {
        files[Self.key(of: row, in: bucket)]
    }

    /// Notes the file of the row on the server, or that the row has none.
    func note(_ file: File?, of row: UUID, in bucket: ServerFile.Bucket) {
        files[Self.key(of: row, in: bucket)] = file
    }

    /// Forgets every file, so that each file uploads again.
    func forgetAll() {
        files = [:]
        save()
    }

    /// Keeps the list in the user defaults.
    func save() {
        defaults.set(files.mapValues { ["path": $0.path, "hash": $0.hash] }, forKey: Self.key)
    }

    /// Takes over the list before #127. The ID of the row is the name of the
    /// file in its path: "<pack>/<walk>" for a GPS track and
    /// "<pack>/<dog>.jpg" for a photo.
    private func convert(_ hashesByPath: [String: String]) {
        for (bucketAndPath, hash) in hashesByPath {
            let parts = bucketAndPath.split(separator: "/", maxSplits: 1)
            guard parts.count == 2, let bucket = ServerFile.Bucket(rawValue: String(parts[0])) else { continue }
            let path = String(parts[1])
            let name = path.split(separator: "/").last ?? ""
            guard let row = UUID(uuidString: String(name.hasSuffix(".jpg") ? name.dropLast(4) : name)) else { continue }
            note(File(path: path, hash: hash), of: row, in: bucket)
        }
        save()
        defaults.removeObject(forKey: Self.keyByPath)
    }

    private static func key(of row: UUID, in bucket: ServerFile.Bucket) -> String {
        "\(bucket.rawValue)/\(row.uuidString)"
    }
}

extension SHA256 {
    /// The hash of the data in lowercase hex digits.
    nonisolated static func hex(of data: Data) -> String {
        hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
