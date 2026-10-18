//
//  PackDownload.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 12.10.2026.
//

import CryptoKit
import Foundation
import SwiftData

/// Downloads the changes of the pack (ADR 0006): the name of the pack, the
/// dogs with their photos, the ended walks with their GPS tracks, the dogs
/// of the walks, the completed records, the area steps, the ring stamps and
/// the weekly goals. `Account` runs it after the upload. The collections
/// then follow from the walks on this phone (ADR 0002).
///
/// A download asks for the rows that changed since the latest change that
/// this phone has stored (`DownloadCursors`), with some overlap. A
/// downloaded row replaces the row with the same ID, so a row that comes
/// twice changes nothing. A deleted row comes with its deletion time.
///
/// A row that waits to upload keeps its change. Its upload comes later, so
/// it wins on the server, and the other phones download it from there.
///
/// A row that cannot be stored, because its GPS track fails to download or a
/// row that it points to is missing, waits for the next download. A dog
/// whose photo fails to download is stored without the new photo. Until then,
/// the download of its table asks again from the same latest change.
///
/// A file downloads from the path in its row, also from the folder of a pack
/// that moved. The phone notes the path (`UploadedFiles`), so that a photo
/// downloads only when its path is new, and so that this phone can delete
/// the file later. A row whose file Storage does not have is stored without
/// the file, and the phone notes the path, so that it does not ask again.
final class PackDownload {
    private let context: ModelContext
    private let server: any Server
    /// The pack of the account, which is the pack of the phone after the
    /// download.
    private let packID: UUID
    private let uploadedFiles: UploadedFiles
    private let cursors: DownloadCursors
    /// The latest change of each table whose rows are all stored now.
    private var latestChanges: [ServerTable: Date] = [:]
    /// The first failure of this download.
    private var failure: (any Error)?

    /// How far back from the latest stored change a download asks again. A
    /// row gets the time of its change when its transaction starts, so a
    /// row that a slow upload saves after a download can have a time before
    /// the latest change of that download.
    static let overlap: TimeInterval = 5 * 60

    init(
        context: ModelContext, server: any Server, packID: UUID, uploadedFiles: UploadedFiles,
        cursors: DownloadCursors
    ) {
        self.context = context
        self.server = server
        self.packID = packID
        self.uploadedFiles = uploadedFiles
        self.cursors = cursors
    }

    /// Downloads and stores the changes, and saves. It throws the first
    /// failure after it has tried every row.
    ///
    /// The download has three phases: the rows of the tables, then the files
    /// that the rows need, four at a time (`FileTransfers`), and then the
    /// store of every row at once. So no row on this phone changes while it
    /// is stored.
    func run() async throws {
        defer {
            uploadedFiles.save()
        }
        async let serverPack = server.pack(id: packID)
        // A row points only to rows that were on the server before it. So
        // the tables whose rows point to other rows download first, and each
        // row that they point to comes with a later table, if this phone
        // does not have it yet.
        var tables: [TableSteps] = []
        for table in SyncedRows.tables.reversed() {
            tables.insert(try await download(table), at: 0)
        }
        // A person who is no member of the pack any more gets no pack.
        guard let serverPack = try await serverPack else { return }

        for table in tables {
            try await table.downloadFiles()
        }

        // A dog added during the download makes a pack of its own. Its dogs
        // first have to move into the pack of the account (ADR 0005).
        if let pack = try Pack.ofThisPhone(in: context), pack.id != packID { return }
        let pack = try Self.storePack(serverPack, in: context)
        for table in tables {
            try table.store(pack)
        }
        if context.hasChanges {
            try context.save()
        }
        for (table, date) in latestChanges {
            cursors.noteLatestChange(date, of: table, in: packID)
        }
        if let failure {
            throw failure
        }
    }

    /// Downloads the rows of the table that changed since the latest stored
    /// change, with the overlap, or all its rows before the first download.
    /// It returns the steps that download their files and store them.
    private func download<Row: SyncedRow>(_ table: Row.Type) async throws -> TableSteps {
        let since = cursors.latestChange(of: Row.table, in: packID).map { $0 - Self.overlap }
        let rows = TableRows(try await server.download(table, of: packID, changedSince: since))
        return TableSteps(
            downloadFiles: { try await self.downloadFiles(of: rows) },
            store: { try self.store(rows, in: $0) })
    }

    /// Makes the pack of the account the pack of the phone, or gives the
    /// pack of the phone the name and the home base on the server. A pack
    /// whose change waits to upload keeps its name, and a home base that a
    /// member moved on this phone stays until it has uploaded.
    static func storePack(_ row: ServerPack, in context: ModelContext) throws -> Pack {
        let id = row.id
        let stored = try context.fetch(FetchDescriptor<Pack>(predicate: #Predicate { $0.id == id })).first
        let pack = stored ?? {
            let pack = Pack(id: row.id, name: row.name, createdAt: row.createdAt)
            pack.isWaitingToUpload = false
            context.insert(pack)
            return pack
        }()
        if !pack.isWaitingToUpload {
            pack.set(\.name, to: row.name)
        }
        if !pack.isHomeBaseWaitingToUpload, let homeBase = row.homeBase {
            pack.set(\.homeLatitude, to: homeBase.latitude)
            pack.set(\.homeLongitude, to: homeBase.longitude)
            pack.set(\.homeSetAt, to: row.homeSetAt)
        }
        return pack
    }

    /// Downloads the files that the rows of a table with files need, four at
    /// a time, from the path in each row. A file at a path that this phone
    /// has noted stays, and a file that never changes downloads only when
    /// this phone does not have it.
    private func downloadFiles<Row: SyncedRow>(of table: TableRows<Row>) async throws {
        guard let file = Row.file else { return }
        let stored = try Row.localRows(withIDs: Set(table.rows.map(\.row.id)), in: context)
        table.stored = stored
        var paths: [UUID: String] = [:]
        for row in table.rows.map(\.row) where stored[row.id]?.isWaitingToUpload != true {
            guard let path = row[keyPath: file.path] else { continue }
            if file.neverChanges, stored[row.id]?[keyPath: file.data] != nil { continue }
            if uploadedFiles.file(of: row.id, in: file.bucket)?.path != path {
                paths[row.id] = path
            }
        }
        let bucket = file.bucket
        table.files = await FileTransfers.run(paths) { _, path in
            try await self.server.downloadFile(ServerFile(bucket: bucket, path: path))
        }
    }

    /// Stores the rows of the table, with their files. A row whose target is
    /// not on this phone waits for the next download. In a table with a
    /// unique key, a local row with the key of a downloaded row and another
    /// ID leaves this phone, also when it waits to upload: the server refused
    /// it, or will refuse it.
    private func store<Row: SyncedRow>(_ table: TableRows<Row>, in pack: Pack) throws {
        let rows = table.rows
        let ids = Set(rows.map(\.row.id))
        let stored = try table.stored ?? Row.localRows(withIDs: ids, in: context)
        let targets = StoreTargets(
            pack: pack, rows: try SyncedRows.localRows(of: rows.flatMap(\.row.targets), in: context))
        let others = try Row.hasUniqueKey
            ? context.fetch(FetchDescriptor<Row.Local>()).filter { !ids.contains($0.id) } : []
        let file = Row.file
        var locals = stored
        store(rows, over: stored) { downloaded in
            let row = downloaded.row
            if let missing = row.targets.first(where: { targets.rows[$0.id] == nil }) {
                throw MissingRow(table: missing.table, id: missing.id)
            }
            let storedFile = try file.map { try self.storedFile(of: row, in: table, stored: locals[row.id], file: $0) }
            let local = try row.store(
                in: locals[row.id], targets: targets, changedAt: downloaded.changedAt, context: context)
            locals[row.id] = local
            if let file, let storedFile {
                local.set(file.data, to: storedFile.data)
            }
            if row.deletedAt == nil {
                for other in others where row.hasSameKey(as: other) {
                    context.delete(other)
                }
            }
            // A row whose file fails to download is stored without the new
            // file. The phone keeps the path of the old file, so the next
            // download of the table gets the new one.
            if let failure = storedFile?.failure {
                throw failure
            }
            if let file, let storedFile {
                noteOnServer(
                    storedFile.isMissing ? nil : storedFile.data, at: row[keyPath: file.path], of: row.id,
                    in: file.bucket)
            }
        }
    }

    /// The file of a downloaded row: the downloaded file, or the file of this
    /// phone. A row without a file in Storage has none. A file that Storage
    /// does not have leaves the file of this phone as it is. A row whose file
    /// is still needed and did not download throws `MissingFile`.
    private func storedFile<Row: SyncedRow>(
        of row: Row, in table: TableRows<Row>, stored local: Row.Local?, file: SyncedFile<Row>
    ) throws -> StoredFile {
        guard let path = row[keyPath: file.path] else { return StoredFile(data: nil) }
        var stored = StoredFile(data: local?[keyPath: file.data])
        if file.neverChanges, stored.data != nil {
            return stored
        }
        if let download = table.files[row.id] {
            do {
                stored.data = try download.get()
            } catch is FileMissing {
                stored.isMissing = true
            } catch where file.storesRowWithoutFile {
                stored.failure = error
            }
        } else if file.neverChanges, uploadedFiles.file(of: row.id, in: file.bucket)?.path != path {
            // The file did not download, and no earlier download found that
            // Storage does not have it.
            throw MissingFile(row: row.id)
        }
        return stored
    }

    /// Stores each row, unless its row on this phone waits to upload: that
    /// change uploads later, so it wins on the server, and the other phones
    /// download it from there. It keeps the failure of a row that cannot be
    /// stored, and notes the latest change of the table only when every row
    /// is stored.
    ///
    /// - Parameter stored: The rows on this phone with the IDs of the rows.
    private func store<Row: ServerRow, Local: UploadingRow>(
        _ rows: [Downloaded<Row>], over stored: [UUID: Local], with storeRow: (Downloaded<Row>) throws -> Void
    ) {
        var storedAll = true
        for row in rows where stored[row.row.id]?.isWaitingToUpload != true {
            do {
                try storeRow(row)
            } catch {
                failure = failure ?? error
                storedAll = false
            }
        }
        if storedAll, let latest = rows.map(\.changedAt).max() {
            latestChanges[Row.table] = latest
        }
    }

    /// Notes the file of the row that is on the server now, so that the next
    /// upload of the row uploads the file only when it has changed, and
    /// deletes it at its path when this phone removes it. A file at a path
    /// that the phone has noted already has the noted content.
    ///
    /// - Parameters:
    ///   - data: The content of the file, or nil when Storage does not have
    ///     the file at the path.
    ///   - path: The path in the row, or nil for a row without a file.
    private func noteOnServer(_ data: Data?, at path: String?, of row: UUID, in bucket: ServerFile.Bucket) {
        guard let path else {
            uploadedFiles.note(nil, of: row, in: bucket)
            return
        }
        guard uploadedFiles.file(of: row, in: bucket)?.path != path else { return }
        uploadedFiles.note(UploadedFiles.File(path: path, hash: data.map(SHA256.hex(of:)) ?? ""), of: row, in: bucket)
    }
}

/// The steps of the download of one table after its rows have come: the
/// download of their files, and their store in the pack of the phone.
private struct TableSteps {
    var downloadFiles: () async throws -> Void
    var store: (Pack) throws -> Void
}

/// The downloaded rows of one table, until they are stored.
private final class TableRows<Row: SyncedRow> {
    let rows: [Downloaded<Row>]
    /// The rows of this phone with the IDs of the rows, which a table with
    /// files fetches before its files.
    var stored: [UUID: Row.Local]?
    /// The downloaded files, by the IDs of their rows.
    var files: [UUID: Result<Data, any Error>] = [:]

    init(_ rows: [Downloaded<Row>]) {
        self.rows = rows
    }
}

/// The file that a downloaded row stores.
private struct StoredFile {
    /// The content, or nil for a row without a file.
    var data: Data?
    /// Whether Storage does not have the file at the path of the row.
    var isMissing = false
    /// Why the new file did not download, for a row that is stored without
    /// it.
    var failure: (any Error)?
}

/// The file of a downloaded row did not download.
private struct MissingFile: Error {
    var row: UUID
}
