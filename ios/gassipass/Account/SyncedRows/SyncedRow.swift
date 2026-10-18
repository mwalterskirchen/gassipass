//
//  SyncedRow.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData

/// A row of the pack that this phone keeps in sync with the server (ADR
/// 0006). Each table of the pack has one such type in this folder, with its
/// columns and its mapping to the local model in both directions.
/// `PackUpload` and `PackDownload` run over the tables in `SyncedRows.tables`.
///
/// A row points to other rows (`targets`), for example a dog of a walk to its
/// walk and its dog. A row uploads only when the rows that it points to are on
/// the server, and a local row whose target is gone from the phone stops
/// waiting, because it can never upload. A downloaded row is stored only when
/// this phone has the rows that it points to. Otherwise the row waits for the
/// next download.
protocol SyncedRow: ServerRow {
    /// The model of the row in the local store.
    associatedtype Local: UploadingRow

    /// The time when the row was deleted, or nil.
    var deletedAt: Date? { get }

    /// The local rows that wait to upload.
    static var waitingRows: FetchDescriptor<Local> { get }
    /// The local rows that wait to upload and changed after the start and
    /// up to the end, as `Account` counts them.
    static func waitingRows(changedAfter start: Date, upTo end: Date) -> FetchDescriptor<Local>
    /// The local rows with the IDs.
    static func localRows(withIDs ids: Set<UUID>) -> FetchDescriptor<Local>

    /// The rows that the local row points to, or nil when one of them is gone
    /// from this phone.
    static func targets(of local: Local) -> [SyncedTarget]?
    /// The rows that this row points to.
    var targets: [SyncedTarget] { get }
    /// Whether the local row is on the server, so that the rows that point to
    /// it can upload. By default, it is when it does not wait to upload.
    static func isOnServer(_ local: Local) -> Bool

    /// The file of each row in Storage, or nil for a table without files.
    static var file: SyncedFile<Self>? { get }

    /// Whether the table has a unique key besides the ID, like the weekly
    /// goals (ADR 0007). The server refuses a second row with the same key.
    /// The phone then takes the row of the server for its refused row, and a
    /// downloaded row removes a local row with the same key and another ID.
    static var hasUniqueKey: Bool { get }
    /// Whether the local row has the unique key of this row.
    func hasSameKey(as local: Local) -> Bool

    /// The row of the local row for the server, or nil when it cannot upload.
    ///
    /// - Parameter filePath: The path of the uploaded file of the row, or nil
    ///   for a row without a file.
    init?(_ local: Local, packID: UUID, filePath: String?)

    /// Gives the local row the values of this row, or makes a new local row
    /// with them, which the caller inserts. The file and the deletion time of
    /// the row are not part of it (`store(in:targets:changedAt:context:)`).
    func store(in local: Local?, targets: StoreTargets) throws -> Local
}

extension SyncedRow {
    static func isOnServer(_ local: Local) -> Bool {
        !local.isWaitingToUpload
    }

    static var file: SyncedFile<Self>? {
        nil
    }

    static var hasUniqueKey: Bool {
        false
    }

    func hasSameKey(as local: Local) -> Bool {
        false
    }

    /// The local rows with the IDs, by their IDs.
    static func localRows(withIDs ids: Set<UUID>, in context: ModelContext) throws -> [UUID: Local] {
        Dictionary(try context.fetch(localRows(withIDs: ids)).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Stores the row in the local row, or in a new local row that it
    /// inserts, and notes that the local row is as on the server, so that it
    /// does not upload. It returns the local row.
    func store(in local: Local?, targets: StoreTargets, changedAt: Date, context: ModelContext) throws -> Local {
        let stored = try store(in: local, targets: targets)
        if local == nil {
            context.insert(stored)
        }
        stored.set(\.deletedAt, to: deletedAt)
        stored.set(\.changedAt, to: changedAt)
        stored.set(\.isWaitingToUpload, to: false)
        return stored
    }

    fileprivate static func anyLocalRows(withIDs ids: Set<UUID>, in context: ModelContext) throws
        -> [UUID: any UploadingRow] {
        try localRows(withIDs: ids, in: context).mapValues { $0 }
    }

    fileprivate static func onServer(withIDs ids: Set<UUID>, in context: ModelContext) throws -> [UUID: Bool] {
        try localRows(withIDs: ids, in: context).mapValues(isOnServer)
    }
}

/// The synced tables of the pack.
enum SyncedRows {
    /// The tables in the order of the upload: each table after the tables
    /// that its rows point to. The phone stores downloaded rows in the same
    /// order, and the download asks for the tables in the reverse order, so
    /// that each row that a downloaded row points to comes with a later table.
    static let tables: [any SyncedRow.Type] = [
        ServerDog.self, ServerWalk.self, ServerWalkDog.self, ServerCompletedArea.self, ServerCompletedStreet.self,
        ServerAreaStep.self, ServerCompletedRing.self, ServerGoalSet.self,
    ]

    /// The local rows of the targets that this phone has, by their IDs.
    static func localRows(of targets: some Sequence<SyncedTarget>, in context: ModelContext) throws
        -> [UUID: any UploadingRow] {
        var rows: [UUID: any UploadingRow] = [:]
        for (table, targets) in Dictionary(grouping: targets, by: \.table) {
            let found = try syncedRow(of: table).anyLocalRows(withIDs: Set(targets.map(\.id)), in: context)
            rows.merge(found) { first, _ in first }
        }
        return rows
    }

    /// Whether each target that this phone has is on the server, by its ID.
    static func onServer(_ targets: some Sequence<SyncedTarget>, in context: ModelContext) throws -> [UUID: Bool] {
        var onServer: [UUID: Bool] = [:]
        for (table, targets) in Dictionary(grouping: targets, by: \.table) {
            let found = try syncedRow(of: table).onServer(withIDs: Set(targets.map(\.id)), in: context)
            onServer.merge(found) { first, _ in first }
        }
        return onServer
    }

    private static func syncedRow(of table: ServerTable) -> any SyncedRow.Type {
        guard let row = tables.first(where: { $0.table == table }) else {
            preconditionFailure("No synced table \(table.rawValue)")
        }
        return row
    }
}

/// A row that another row points to.
nonisolated struct SyncedTarget: Hashable, Sendable {
    var table: ServerTable
    var id: UUID

    static func dog(_ id: UUID) -> SyncedTarget {
        SyncedTarget(table: .dogs, id: id)
    }

    static func walk(_ id: UUID) -> SyncedTarget {
        SyncedTarget(table: .walks, id: id)
    }
}

/// The file of each row of a table in Storage: the photo of a dog, or the
/// GPS track of a walk. A file uploads only when it has changed
/// (`UploadedFiles`), and the old file of the row then leaves the server.
struct SyncedFile<Row: SyncedRow> {
    var bucket: ServerFile.Bucket
    /// The content of the file on this phone, or nil for a row without one.
    var data: ReferenceWritableKeyPath<Row.Local, Data?>
    /// The path of the file in the row, or nil for a row without a file.
    var path: KeyPath<Row, String?>
    /// The file for new content of a row, by the ID of the row, the pack and
    /// the hash of the content.
    var newFile: @Sendable (_ row: UUID, _ pack: UUID, _ hash: String) -> ServerFile
    /// Whether the file of a row never changes, like the GPS track of an
    /// ended walk. A phone that has the file never downloads it again.
    var neverChanges: Bool
    /// Whether a row is stored without its new file when the file fails to
    /// download, like a dog, so that the rows that point to it can be stored.
    /// The download of the table then asks again for the row. Otherwise the
    /// row waits for the next download.
    var storesRowWithoutFile: Bool
}

/// What a downloaded row points to on this phone.
struct StoreTargets {
    /// The pack of this phone, which is the pack of the row.
    var pack: Pack
    /// The local rows of the targets, by their IDs.
    var rows: [UUID: any UploadingRow]

    /// The local row of the target. It throws `MissingRow` when this phone
    /// does not have it.
    func local<Target: SyncedRow>(_ type: Target.Type, _ id: UUID) throws -> Target.Local {
        guard let row = rows[id] as? Target.Local else { throw MissingRow(table: Target.table, id: id) }
        return row
    }
}

/// A downloaded row points to a row that this phone does not have.
nonisolated struct MissingRow: Error {
    var table: ServerTable
    var id: UUID
}
