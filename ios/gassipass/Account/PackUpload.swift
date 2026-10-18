//
//  PackUpload.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import CryptoKit
import Foundation
import SwiftData

/// Uploads the rows of the pack that wait to upload (ADR 0006): the dogs
/// with their photos, the ended walks with their GPS tracks, the dogs of the
/// walks, the completed records, the area steps, the ring stamps and the
/// weekly goals. `Account` runs it after the pack of the phone is on the
/// server.
///
/// A photo or GPS track uploads only when it has changed (`UploadedFiles`),
/// and the old file of the row then leaves the server. A row that uploads
/// stops waiting, unless it changed during the upload.
/// A row that fails to upload waits for the next upload, and the other rows
/// upload without it. A failure without a network stops the upload, because
/// every other request would fail too. The files upload four at a time
/// (`FileTransfers`), before the rows of their table. The tables upload in
/// the order of `SyncedRows.tables`, and a row uploads only after the rows
/// that it points to (`SyncedRow`). So the dogs of a walk wait for the walk
/// and for the dogs, and a completed record, an area step, a ring stamp or a
/// set of weekly goals waits for its dog.
final class PackUpload {
    private let context: ModelContext
    private let server: any Server
    /// The pack on the server, which is the pack of the phone.
    private let packID: UUID
    private let uploadedFiles: UploadedFiles
    /// The first failure of this upload.
    private var failure: (any Error)?

    init(context: ModelContext, server: any Server, packID: UUID, uploadedFiles: UploadedFiles) {
        self.context = context
        self.server = server
        self.packID = packID
        self.uploadedFiles = uploadedFiles
    }

    /// Uploads the waiting rows. It throws the first failure after it has
    /// tried every row, or at once without a network.
    func run() async throws {
        defer {
            uploadedFiles.save()
        }
        for table in SyncedRows.tables {
            do {
                try await upload(table)
            } catch {
                keep(error)
                if FileTransfers.isWithoutNetwork(error) {
                    break
                }
            }
        }
        if let failure {
            throw failure
        }
    }

    /// The number of rows that wait to upload and changed after the start
    /// and up to the end. A walk that is still being recorded, and its dogs,
    /// do not count, because they upload only after the walk ends. A change
    /// after the end does not count, so a row with a change time in the
    /// future, for example after the clock went back, does not start upload
    /// after upload.
    static func waitingRows(
        changedAfter start: Date = .distantPast, upTo end: Date = .distantFuture, in context: ModelContext
    ) throws -> Int {
        var count = try context.fetchCount(FetchDescriptor<Pack>(predicate: #Predicate {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        }))
        count += try context.fetchCount(FetchDescriptor<Dog>(predicate: #Predicate {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        }))
        count += try context.fetchCount(FetchDescriptor<Walk>(predicate: #Predicate {
            $0.isWaitingToUpload && $0.endedAt != nil && $0.changedAt > start && $0.changedAt <= end
        }))
        count += try context.fetchCount(FetchDescriptor<WalkDog>(predicate: #Predicate {
            $0.isWaitingToUpload && $0.walk?.endedAt != nil && $0.changedAt > start && $0.changedAt <= end
        }))
        count += try context.fetchCount(FetchDescriptor<CompletedArea>(predicate: #Predicate {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        }))
        count += try context.fetchCount(FetchDescriptor<CompletedStreet>(predicate: #Predicate {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        }))
        count += try context.fetchCount(FetchDescriptor<AreaStep>(predicate: #Predicate {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        }))
        count += try context.fetchCount(FetchDescriptor<CompletedRing>(predicate: #Predicate {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        }))
        count += try context.fetchCount(FetchDescriptor<StoredGoalSet>(predicate: #Predicate {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        }))
        return count
    }

    /// Runs the step, and keeps its failure. It returns whether the step
    /// succeeded.
    @discardableResult
    private func attempt(_ step: () async throws -> Void) async -> Bool {
        do {
            try await step()
            return true
        } catch {
            keep(error)
            return false
        }
    }

    private func keep(_ error: any Error) {
        failure = failure ?? error
    }

    /// Uploads the waiting rows of the table whose targets are on the server,
    /// after their files. For a table with a unique key, a refused row takes
    /// the row of the server with the same key.
    private func upload<Row: SyncedRow>(_ table: Row.Type) async throws {
        // A row that changes during the upload of its file keeps waiting.
        let waiting = try context.fetch(Row.waitingRows).map { (local: $0, changedAt: $0.changedAt) }
        let ready = try withTargetsOnServer(waiting.map(\.local), of: table)
        var filePaths: [UUID: String?] = [:]
        if let file = Row.file {
            let packID = packID
            let newFile = file.newFile
            let files = waiting.filter { ready.contains($0.local.id) }
                .map { (id: $0.local.id, data: $0.local[keyPath: file.data]) }
            filePaths = try await uploadFiles(of: files, in: file.bucket) { newFile($0, packID, $1) }
        }
        var changes: [Change<Row.Local, Row>] = []
        for (local, changedAt) in waiting where ready.contains(local.id) {
            var filePath: String?
            if Row.file != nil {
                // A row whose file failed to upload waits for the next upload.
                guard let path = filePaths[local.id] else { continue }
                filePath = path
            }
            guard let row = Row(local, packID: packID, filePath: filePath) else { continue }
            changes.append(Change(local: local, changedAt: changedAt, row: row))
        }
        guard Row.hasUniqueKey else {
            try await upload(changes)
            return
        }
        do {
            try await upload(changes)
        } catch is RowRefused {
            // A batch of one row throws its refusal.
        }
        let refused = changes.map(\.local).filter(\.isWaitingToUpload)
        guard !refused.isEmpty else { return }
        try await takeServerRows(for: refused, of: table)
    }

    /// The IDs of the local rows whose targets are on the server. A row whose
    /// target is gone from this phone can never upload, so it stops waiting.
    private func withTargetsOnServer<Row: SyncedRow>(_ locals: [Row.Local], of table: Row.Type) throws -> Set<UUID> {
        let targets = locals.map { (local: $0, targets: Row.targets(of: $0)) }
        let onServer = try SyncedRows.onServer(targets.flatMap { $0.targets ?? [] }, in: context)
        var ready: Set<UUID> = []
        for (local, targets) in targets {
            guard let targets, targets.allSatisfy({ onServer[$0.id] != nil }) else {
                local.isWaitingToUpload = false
                continue
            }
            if targets.allSatisfy({ onServer[$0.id] == true }) {
                ready.insert(local.id)
            }
        }
        return ready
    }

    /// Replaces each refused row with the row of the server with the same ID
    /// or the same unique key, because a download skips a row that waits to
    /// upload. A row without one on the server keeps waiting.
    private func takeServerRows<Row: SyncedRow>(for refused: [Row.Local], of table: Row.Type) async throws {
        let rows = try await server.download(table, of: packID, changedSince: nil).filter { $0.row.deletedAt == nil }
        guard let pack = try Pack.ofThisPhone(in: context) else { return }
        let targets = StoreTargets(
            pack: pack, rows: try SyncedRows.localRows(of: rows.flatMap(\.row.targets), in: context))
        for local in refused {
            guard let downloaded = rows.first(where: { $0.row.id == local.id })
                    ?? rows.first(where: { $0.row.hasSameKey(as: local) })
            else { continue }
            let row = downloaded.row
            var stored: Row.Local? = local
            if row.id != local.id {
                context.delete(local)
                stored = try Row.localRows(withIDs: [row.id], in: context)[row.id]
            }
            _ = try row.store(in: stored, targets: targets, changedAt: downloaded.changedAt, context: context)
        }
        if context.hasChanges {
            try context.save()
        }
    }

    /// Uploads the files of the rows, four at a time, and returns the path of
    /// each row whose file has uploaded: the path of the file, or nil for a
    /// row without a file. A row whose file failed has no path, and it waits
    /// for the next upload. A failure without a network stops the upload.
    ///
    /// - Parameter newFile: The file for new content of the row, by the ID
    ///   of the row and the hash of the content.
    private func uploadFiles(
        of rows: [(id: UUID, data: Data?)], in bucket: ServerFile.Bucket,
        newFile: @escaping @Sendable (UUID, String) -> ServerFile
    ) async throws -> [UUID: String?] {
        let data = Dictionary(rows.map { ($0.id, $0.data) }, uniquingKeysWith: { first, _ in first })
        let results = await FileTransfers.run(data) { row, data in
            try await self.upload(data, of: row, in: bucket) { newFile(row, $0) }
        }
        for case .failure(let error) in results.values where FileTransfers.isWithoutNetwork(error) {
            throw error
        }
        var paths: [UUID: String?] = [:]
        for (row, result) in results {
            switch result {
            case .success(let path):
                paths.updateValue(path, forKey: row)
            case .failure(let error):
                keep(error)
            }
        }
        return paths
    }

    /// Uploads the file of the row when it has changed since its last upload
    /// or download, and returns its path, or nil for a row without a file. A
    /// new file goes into the folder of the pack of the phone. The old file
    /// of the row then leaves the server, also from the folder of a pack that
    /// moved. The phone notes the new file only after the old one has left,
    /// so that a failed deletion tries again with the next upload.
    ///
    /// - Parameter newFile: The file for new content, by the hash of the
    ///   content.
    private func upload(
        _ data: Data?, of row: UUID, in bucket: ServerFile.Bucket, newFile: (String) -> ServerFile
    ) async throws -> String? {
        let old = uploadedFiles.file(of: row, in: bucket)
        guard let data else {
            if let old {
                try await server.deleteFile(ServerFile(bucket: bucket, path: old.path))
                uploadedFiles.note(nil, of: row, in: bucket)
            }
            return nil
        }
        let hash = SHA256.hex(of: data)
        if let old, old.hash == hash {
            return old.path
        }
        let file = newFile(hash)
        try await server.uploadFile(data, to: file)
        if let old, old.path != file.path {
            try await server.deleteFile(ServerFile(bucket: bucket, path: old.path))
        }
        uploadedFiles.note(UploadedFiles.File(path: file.path, hash: hash), of: row, in: bucket)
        return file.path
    }

    /// Sends the rows in batches, and notes after each batch that its rows
    /// have uploaded. When the server refuses a row of a batch, the rows of
    /// the batch upload one at a time, so that the refused row waits alone.
    /// Another failure, for example without a network, stops the upload.
    private func upload<LocalRow, Row: ServerRow>(_ changes: [Change<LocalRow, Row>]) async throws {
        // A row that can never upload stopped waiting without an upload.
        if context.hasChanges {
            try context.save()
        }
        for start in stride(from: 0, to: changes.count, by: Self.batchSize) {
            let batch = changes[start..<min(start + Self.batchSize, changes.count)]
            do {
                try await server.upload(batch.map(\.row))
                try markUploaded(batch)
            } catch is RowRefused where batch.count > 1 {
                for change in batch {
                    if await attempt({ try await server.upload([change.row]) }) {
                        try markUploaded([change])
                    }
                }
            }
        }
    }

    /// The number of rows in one request.
    private static let batchSize = 100

    /// Notes that the rows have uploaded, and saves. A row that changed
    /// since the upload started keeps waiting.
    private func markUploaded<LocalRow, Row>(_ changes: some Collection<Change<LocalRow, Row>>) throws {
        for change in changes where change.local.changedAt == change.changedAt {
            change.local.isWaitingToUpload = false
        }
        if context.hasChanges {
            try context.save()
        }
    }
}

/// A local row that uploads, with the time of its change and the row for the
/// server.
private struct Change<LocalRow: UploadingRow, Row> {
    let local: LocalRow
    let changedAt: Date
    let row: Row
}
