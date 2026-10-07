//
//  LocalStore.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 07.10.2026.
//

import Foundation
import SwiftData

/// The SwiftData store on the phone (ADR 0006), with the models of
/// `LocalSchemaV1`. It never syncs with iCloud: the rows upload to the
/// server on their own.
enum LocalStore {
    static let schema = Schema(versionedSchema: LocalSchemaV1.self)

    /// Opens the store in the file, or creates it.
    static func container(at url: URL) throws -> ModelContainer {
        // The app still has the iCloud entitlement, and SwiftData would sync
        // with it by default.
        try ModelContainer(for: schema, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
    }
}
