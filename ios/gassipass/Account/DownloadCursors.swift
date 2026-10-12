//
//  DownloadCursors.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 12.10.2026.
//

import Foundation

/// The latest change on the server that this phone has stored, for each
/// table of the pack, so that the next download asks only for the rows that
/// changed since. The user defaults keep them, so they survive a restart of
/// the app. They belong to one pack, so the download of another pack starts
/// with all its rows.
final class DownloadCursors {
    enum Table: String, CaseIterable {
        case dogs, walks
        case walkDogs = "walk_dogs"
        case completedAreas = "completed_areas"
        case completedStreets = "completed_streets"
    }

    private let defaults: UserDefaults
    /// The latest stored change, by pack and table.
    private var dates: [String: Date]

    private static let key = "downloadCursors"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        dates = defaults.dictionary(forKey: Self.key) as? [String: Date] ?? [:]
    }

    /// The latest change of the table that this phone has stored, or nil
    /// before the first download of the pack.
    func latestChange(of table: Table, in pack: UUID) -> Date? {
        dates[Self.key(of: table, in: pack)]
    }

    /// Notes the latest change of the table, and keeps it in the user
    /// defaults.
    func noteLatestChange(_ date: Date, of table: Table, in pack: UUID) {
        dates[Self.key(of: table, in: pack)] = date
        defaults.set(dates, forKey: Self.key)
    }

    private static func key(of table: Table, in pack: UUID) -> String {
        "\(pack.uuidString)/\(table.rawValue)"
    }
}
