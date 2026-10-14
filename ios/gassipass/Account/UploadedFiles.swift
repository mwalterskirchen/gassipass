//
//  UploadedFiles.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import CryptoKit
import Foundation

/// The files that this phone has uploaded to Storage, each with a hash of its
/// content. A row that changes uploads again, but its photo or GPS track
/// uploads again only when the file has changed. The user defaults keep the
/// list, so it survives a restart of the app.
final class UploadedFiles {
    private let defaults: UserDefaults
    /// The hash of the content of each uploaded file, by its bucket and path.
    private var hashes: [String: String]

    private static let key = "uploadedFiles"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        hashes = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    /// Whether the file is on the server with this content.
    func contains(_ data: Data, at file: ServerFile) -> Bool {
        hashes[Self.key(of: file)] == SHA256.hex(of: data)
    }

    /// Whether a file is on the server at the path.
    func contains(_ file: ServerFile) -> Bool {
        hashes[Self.key(of: file)] != nil
    }

    func noteUploaded(_ data: Data, at file: ServerFile) {
        hashes[Self.key(of: file)] = SHA256.hex(of: data)
    }

    func noteDeleted(_ file: ServerFile) {
        hashes[Self.key(of: file)] = nil
    }

    /// Forgets every file, so that each file uploads again.
    func forgetAll() {
        hashes = [:]
        save()
    }

    /// Keeps the list in the user defaults.
    func save() {
        defaults.set(hashes, forKey: Self.key)
    }

    private static func key(of file: ServerFile) -> String {
        "\(file.bucket)/\(file.path)"
    }
}

extension SHA256 {
    /// The hash of the data in lowercase hex digits.
    static func hex(of data: Data) -> String {
        hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
