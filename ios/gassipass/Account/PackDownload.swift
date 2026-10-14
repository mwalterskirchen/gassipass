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
/// of the walks and the completed records. `Account` runs it after the
/// upload. The collections then follow from the walks on this phone
/// (ADR 0002).
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
/// the file later.
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
    func run() async throws {
        defer {
            uploadedFiles.save()
        }
        // A row points only to rows that were on the server before it. So
        // the tables whose rows point to other rows download first, and each
        // row that they point to comes with a later table, if this phone
        // does not have it yet.
        let completedAreas = try await server.downloadCompletedAreas(
            of: packID, changedSince: since(.completedAreas))
        let completedStreets = try await server.downloadCompletedStreets(
            of: packID, changedSince: since(.completedStreets))
        let walkDogs = try await server.downloadWalkDogs(of: packID, changedSince: since(.walkDogs))
        let walks = try await server.downloadWalks(of: packID, changedSince: since(.walks))
        let dogs = try await server.downloadDogs(of: packID, changedSince: since(.dogs))
        // A person who is no member of the pack any more gets no pack.
        guard let serverPack = try await server.pack(id: packID) else { return }
        // A dog added during the download makes a pack of its own. Its dogs
        // first have to move into the pack of the account (ADR 0005).
        if let pack = try Pack.ofThisPhone(in: context), pack.id != packID { return }

        let pack = try Self.storePack(serverPack, in: context)
        try await storeDogs(dogs, in: pack)
        try await storeWalks(walks)
        try await storeWalkDogs(walkDogs)
        try await storeCompletedAreas(completedAreas)
        try await storeCompletedStreets(completedStreets)
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

    /// The date from which the download of the table asks, or nil for all
    /// rows.
    private func since(_ table: ServerTable) -> Date? {
        cursors.latestChange(of: table, in: packID).map { $0 - Self.overlap }
    }

    /// Makes the pack of the account the pack of the phone, or gives the
    /// pack of the phone the name on the server.
    static func storePack(_ row: ServerPack, in context: ModelContext) throws -> Pack {
        let id = row.id
        if let pack = try context.fetch(FetchDescriptor<Pack>(predicate: #Predicate { $0.id == id })).first {
            if !pack.isWaitingToUpload {
                pack.set(\.name, to: row.name)
            }
            return pack
        }
        let pack = Pack(id: row.id, name: row.name, createdAt: row.createdAt)
        pack.isWaitingToUpload = false
        context.insert(pack)
        return pack
    }

    private func storeDogs(_ rows: [Downloaded<ServerDog>], in pack: Pack) async throws {
        let ids = Set(rows.map(\.row.id))
        var dogs = try byID(context.fetch(FetchDescriptor<Dog>(predicate: #Predicate { ids.contains($0.id) })))
        await store(rows) { downloaded in
            let row = downloaded.row
            guard dogs[row.id]?.isWaitingToUpload != true else { return }
            // Each photo has a path of its own, so a photo that this phone
            // has stored from the same path stays.
            var photo = dogs[row.id]?.photoData
            var photoFailure: (any Error)?
            if let path = row.photoPath {
                if photo == nil || uploadedFiles.file(of: row.id, in: .dogPhotos)?.path != path {
                    do {
                        photo = try await server.downloadFile(ServerFile(bucket: .dogPhotos, path: path))
                    } catch {
                        photoFailure = error
                    }
                }
            } else {
                photo = nil
            }
            // The dog can change during the download of its photo.
            guard dogs[row.id]?.isWaitingToUpload != true else { return }
            let dog = dogs[row.id] ?? insert(Dog(id: row.id, name: row.name))
            dogs[row.id] = dog
            dog.set(\.name, to: row.name)
            dog.set(\.photoData, to: photo)
            dog.set(\.retiredAt, to: row.retiredAt)
            dog.set(\.retirementReason, to: row.retirementReason)
            if dog.pack?.id != pack.id {
                dog.pack = pack
            }
            noteStored(dog, deletedAt: row.deletedAt, changedAt: downloaded.changedAt)
            // A dog whose photo fails to download is stored without the new
            // photo, so that its walks and records can point to it. The phone
            // keeps the path of the old photo, so the next download of the
            // table gets the new one.
            if let photoFailure {
                throw photoFailure
            }
            noteOnServer(photo, at: row.photoPath, of: row.id, in: .dogPhotos)
        }
    }

    private func storeWalks(_ rows: [Downloaded<ServerWalk>]) async throws {
        let ids = Set(rows.map(\.row.id))
        var walks = try byID(context.fetch(FetchDescriptor<Walk>(predicate: #Predicate { ids.contains($0.id) })))
        await store(rows) { downloaded in
            let row = downloaded.row
            guard walks[row.id]?.isWaitingToUpload != true else { return }
            // The GPS track of an ended walk never changes, so it downloads
            // only when this phone does not have it. A deleted walk has no
            // GPS track on the server, so it loses it on the phone too.
            let track: Data?
            if let path = row.trackPath {
                if let stored = walks[row.id]?.trackData {
                    track = stored
                } else {
                    track = try await server.downloadFile(ServerFile(bucket: .tracks, path: path))
                }
            } else {
                track = nil
            }
            // The walk can change during the download of its GPS track.
            guard walks[row.id]?.isWaitingToUpload != true else { return }
            let walk = walks[row.id] ?? insert(Walk(id: row.id, startedAt: row.startedAt))
            walks[row.id] = walk
            walk.set(\.startedAt, to: row.startedAt)
            walk.set(\.endedAt, to: row.endedAt)
            walk.set(\.trackData, to: track)
            walk.set(\.distanceMetres, to: row.distanceMetres)
            walk.set(\.distanceVersion, to: row.distanceVersion)
            walk.set(\.continuedAt, to: row.continuedAt)
            walk.set(\.deviceID, to: row.deviceID)
            walk.set(\.memberName, to: row.memberName)
            noteStored(walk, deletedAt: row.deletedAt, changedAt: downloaded.changedAt)
            noteOnServer(track, at: row.trackPath, of: row.id, in: .tracks)
        }
    }

    private func storeWalkDogs(_ rows: [Downloaded<ServerWalkDog>]) async throws {
        let ids = Set(rows.map(\.row.id))
        let walkIDs = Set(rows.map(\.row.walkID))
        let dogIDs = Set(rows.map(\.row.dogID))
        var walkDogs = try byID(context.fetch(FetchDescriptor<WalkDog>(predicate: #Predicate { ids.contains($0.id) })))
        let walks = try byID(context.fetch(FetchDescriptor<Walk>(predicate: #Predicate { walkIDs.contains($0.id) })))
        let dogs = try byID(context.fetch(FetchDescriptor<Dog>(predicate: #Predicate { dogIDs.contains($0.id) })))
        await store(rows) { downloaded in
            let row = downloaded.row
            guard walkDogs[row.id]?.isWaitingToUpload != true else { return }
            guard let walk = walks[row.walkID] else { throw MissingRow(table: .walks, id: row.walkID) }
            guard let dog = dogs[row.dogID] else { throw MissingRow(table: .dogs, id: row.dogID) }
            let walkDog = walkDogs[row.id] ?? insert(WalkDog(id: row.id, walk: walk, dog: dog))
            walkDogs[row.id] = walkDog
            if walkDog.walk?.id != walk.id {
                walkDog.walk = walk
            }
            if walkDog.dog?.id != dog.id {
                walkDog.dog = dog
            }
            noteStored(walkDog, deletedAt: row.deletedAt, changedAt: downloaded.changedAt)
        }
    }

    private func storeCompletedAreas(_ rows: [Downloaded<ServerCompletedArea>]) async throws {
        let ids = Set(rows.map(\.row.id))
        let stored = try context.fetch(FetchDescriptor<CompletedArea>(predicate: #Predicate { ids.contains($0.id) }))
        try await storeRecords(rows, stored: stored) { row, dog in
            CompletedArea(id: row.id, dog: dog, area: row.area, completedAt: row.completedAt)
        } update: { record, row in
            record.set(\.area, to: row.area)
            record.set(\.completedAt, to: row.completedAt)
        }
    }

    private func storeCompletedStreets(_ rows: [Downloaded<ServerCompletedStreet>]) async throws {
        let ids = Set(rows.map(\.row.id))
        let stored = try context.fetch(FetchDescriptor<CompletedStreet>(predicate: #Predicate {
            ids.contains($0.id)
        }))
        try await storeRecords(rows, stored: stored) { row, dog in
            CompletedStreet(
                id: row.id, dog: dog, street: Street.ID(area: row.area, name: row.street), completedAt: row.completedAt)
        } update: { record, row in
            record.set(\.area, to: row.area)
            record.set(\.street, to: row.street)
            record.set(\.completedAt, to: row.completedAt)
        }
    }

    /// Stores the completed records of one kind, which each point to a dog.
    ///
    /// - Parameters:
    ///   - stored: The records on this phone with the IDs of the rows.
    ///   - make: Makes a new record of the dog.
    ///   - update: Gives a stored record the values of the row.
    private func storeRecords<Row: ServerRecord, Record: StoredRecord>(
        _ rows: [Downloaded<Row>], stored: [Record], make: (Row, Dog) -> Record, update: (Record, Row) -> Void
    ) async throws {
        let dogIDs = Set(rows.map(\.row.dogID))
        let dogs = try byID(context.fetch(FetchDescriptor<Dog>(predicate: #Predicate { dogIDs.contains($0.id) })))
        var records = byID(stored)
        await store(rows) { downloaded in
            let row = downloaded.row
            guard records[row.id]?.isWaitingToUpload != true else { return }
            guard let dog = dogs[row.dogID] else { throw MissingRow(table: .dogs, id: row.dogID) }
            let record = records[row.id] ?? insert(make(row, dog))
            records[row.id] = record
            if record.dog?.id != dog.id {
                record.dog = dog
            }
            update(record, row)
            noteStored(record, deletedAt: row.deletedAt, changedAt: downloaded.changedAt)
        }
    }

    /// Stores each row, and keeps the failure of a row that cannot be
    /// stored. It notes the latest change of the table only when every row
    /// is stored.
    private func store<Row: ServerRow>(
        _ rows: [Downloaded<Row>], with storeRow: (Downloaded<Row>) async throws -> Void
    ) async {
        var storedAll = true
        for row in rows {
            do {
                try await storeRow(row)
            } catch {
                failure = failure ?? error
                storedAll = false
            }
        }
        if storedAll, let latest = rows.map(\.changedAt).max() {
            latestChanges[Row.table] = latest
        }
    }

    private func insert<Row: UploadingRow>(_ row: Row) -> Row {
        context.insert(row)
        return row
    }

    /// Notes that the row is as on the server, so that it does not upload.
    private func noteStored(_ row: some UploadingRow, deletedAt: Date?, changedAt: Date) {
        row.set(\.deletedAt, to: deletedAt)
        row.set(\.changedAt, to: changedAt)
        row.set(\.isWaitingToUpload, to: false)
    }

    /// Notes the file of the row that is on the server now, so that the next
    /// upload of the row uploads the file only when it has changed, and
    /// deletes it at its path when this phone removes it. A file at a path
    /// that the phone has noted already has the noted content.
    private func noteOnServer(_ data: Data?, at path: String?, of row: UUID, in bucket: ServerFile.Bucket) {
        guard let data, let path else {
            uploadedFiles.note(nil, of: row, in: bucket)
            return
        }
        guard uploadedFiles.file(of: row, in: bucket)?.path != path else { return }
        uploadedFiles.note(UploadedFiles.File(path: path, hash: SHA256.hex(of: data)), of: row, in: bucket)
    }

    private func byID<Row: UploadingRow>(_ rows: [Row]) -> [UUID: Row] {
        Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// A completed record on the server.
nonisolated private protocol ServerRecord: ServerRow {
    var dogID: UUID { get }
    var deletedAt: Date? { get }
}

extension ServerCompletedArea: ServerRecord {}
extension ServerCompletedStreet: ServerRecord {}

/// A completed record on this phone.
nonisolated private protocol StoredRecord: UploadingRow {
    var dog: Dog? { get set }
}

extension CompletedArea: StoredRecord {}
extension CompletedStreet: StoredRecord {}

/// A downloaded row points to a row that this phone does not have.
private struct MissingRow: Error {
    var table: ServerTable
    var id: UUID
}
