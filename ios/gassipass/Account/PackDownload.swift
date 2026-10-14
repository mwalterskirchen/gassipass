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
        let completedAreas = try await server.downloadCompletedAreas(
            of: packID, changedSince: since(.completedAreas))
        let completedStreets = try await server.downloadCompletedStreets(
            of: packID, changedSince: since(.completedStreets))
        let walkDogs = try await server.downloadWalkDogs(of: packID, changedSince: since(.walkDogs))
        let walks = try await server.downloadWalks(of: packID, changedSince: since(.walks))
        let dogs = try await server.downloadDogs(of: packID, changedSince: since(.dogs))
        // A person who is no member of the pack any more gets no pack.
        guard let serverPack = try await serverPack else { return }

        let dogIDs = Set(dogs.map(\.row.id))
        let storedDogs = try byID(context.fetch(FetchDescriptor<Dog>(predicate: #Predicate { dogIDs.contains($0.id) })))
        let walkIDs = Set(walks.map(\.row.id))
        let storedWalks = try byID(context.fetch(FetchDescriptor<Walk>(predicate: #Predicate {
            walkIDs.contains($0.id)
        })))
        let photos = await downloadPhotos(of: dogs, stored: storedDogs)
        let tracks = await downloadTracks(of: walks, stored: storedWalks)

        // A dog added during the download makes a pack of its own. Its dogs
        // first have to move into the pack of the account (ADR 0005).
        if let pack = try Pack.ofThisPhone(in: context), pack.id != packID { return }
        let pack = try Self.storePack(serverPack, in: context)
        storeDogs(dogs, stored: storedDogs, photos: photos, in: pack)
        storeWalks(walks, stored: storedWalks, tracks: tracks)
        try storeWalkDogs(walkDogs)
        try storeCompletedAreas(completedAreas)
        try storeCompletedStreets(completedStreets)
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

    /// Downloads the photos that the dogs need. Each photo has a path of its
    /// own, so a photo that this phone has noted at the same path stays.
    private func downloadPhotos(
        of rows: [Downloaded<ServerDog>], stored dogs: [UUID: Dog]
    ) async -> [UUID: Result<Data, any Error>] {
        var paths: [UUID: String] = [:]
        for row in rows.map(\.row) where dogs[row.id]?.isWaitingToUpload != true {
            if let path = row.photoPath, uploadedFiles.file(of: row.id, in: .dogPhotos)?.path != path {
                paths[row.id] = path
            }
        }
        return await downloadFiles(at: paths, in: .dogPhotos)
    }

    /// Downloads the GPS tracks that the walks need. The GPS track of an
    /// ended walk never changes, so it downloads only when this phone does
    /// not have it, and when Storage did not miss it before.
    private func downloadTracks(
        of rows: [Downloaded<ServerWalk>], stored walks: [UUID: Walk]
    ) async -> [UUID: Result<Data, any Error>] {
        var paths: [UUID: String] = [:]
        for row in rows.map(\.row) where walks[row.id]?.isWaitingToUpload != true {
            if let path = row.trackPath, walks[row.id]?.trackData == nil,
               uploadedFiles.file(of: row.id, in: .tracks)?.path != path {
                paths[row.id] = path
            }
        }
        return await downloadFiles(at: paths, in: .tracks)
    }

    /// Downloads the file of each row from its path, four at a time. A file
    /// downloads also from the folder of a pack that moved.
    private func downloadFiles(
        at paths: [UUID: String], in bucket: ServerFile.Bucket
    ) async -> [UUID: Result<Data, any Error>] {
        await FileTransfers.run(paths) { _, path in
            try await self.server.downloadFile(ServerFile(bucket: bucket, path: path))
        }
    }

    private func storeDogs(
        _ rows: [Downloaded<ServerDog>], stored: [UUID: Dog], photos: [UUID: Result<Data, any Error>], in pack: Pack
    ) {
        var dogs = stored
        store(rows, over: stored) { downloaded in
            let row = downloaded.row
            var photo = dogs[row.id]?.photoData
            var photoFailure: (any Error)?
            // A photo that Storage does not have leaves the photo of the
            // phone as it is.
            var isPhotoMissing = false
            if row.photoPath == nil {
                photo = nil
            } else if let download = photos[row.id] {
                do {
                    photo = try download.get()
                } catch is FileMissing {
                    isPhotoMissing = true
                } catch {
                    photoFailure = error
                }
            }
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
            noteOnServer(isPhotoMissing ? nil : photo, at: row.photoPath, of: row.id, in: .dogPhotos)
        }
    }

    private func storeWalks(
        _ rows: [Downloaded<ServerWalk>], stored: [UUID: Walk], tracks: [UUID: Result<Data, any Error>]
    ) {
        var walks = stored
        store(rows, over: stored) { downloaded in
            let row = downloaded.row
            // A deleted walk has no GPS track on the server, so it loses it on
            // the phone too.
            let track: Data?
            if let path = row.trackPath {
                if let stored = walks[row.id]?.trackData {
                    track = stored
                } else if let download = tracks[row.id] {
                    do {
                        track = try download.get()
                    } catch is FileMissing {
                        track = nil
                    }
                } else if uploadedFiles.file(of: row.id, in: .tracks)?.path == path {
                    // An earlier download found that Storage does not have it.
                    track = nil
                } else {
                    throw MissingTrack(walk: row.id)
                }
            } else {
                track = nil
            }
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

    private func storeWalkDogs(_ rows: [Downloaded<ServerWalkDog>]) throws {
        let ids = Set(rows.map(\.row.id))
        let walkIDs = Set(rows.map(\.row.walkID))
        let dogIDs = Set(rows.map(\.row.dogID))
        let stored = try byID(context.fetch(FetchDescriptor<WalkDog>(predicate: #Predicate { ids.contains($0.id) })))
        let walks = try byID(context.fetch(FetchDescriptor<Walk>(predicate: #Predicate { walkIDs.contains($0.id) })))
        let dogs = try byID(context.fetch(FetchDescriptor<Dog>(predicate: #Predicate { dogIDs.contains($0.id) })))
        var walkDogs = stored
        store(rows, over: stored) { downloaded in
            let row = downloaded.row
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

    private func storeCompletedAreas(_ rows: [Downloaded<ServerCompletedArea>]) throws {
        let ids = Set(rows.map(\.row.id))
        let stored = try context.fetch(FetchDescriptor<CompletedArea>(predicate: #Predicate { ids.contains($0.id) }))
        try storeRecords(rows, stored: stored) { row, dog in
            CompletedArea(id: row.id, dog: dog, area: row.area, completedAt: row.completedAt)
        } update: { record, row in
            record.set(\.area, to: row.area)
            record.set(\.completedAt, to: row.completedAt)
        }
    }

    private func storeCompletedStreets(_ rows: [Downloaded<ServerCompletedStreet>]) throws {
        let ids = Set(rows.map(\.row.id))
        let stored = try context.fetch(FetchDescriptor<CompletedStreet>(predicate: #Predicate {
            ids.contains($0.id)
        }))
        try storeRecords(rows, stored: stored) { row, dog in
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
    ) throws {
        let dogIDs = Set(rows.map(\.row.dogID))
        let dogs = try byID(context.fetch(FetchDescriptor<Dog>(predicate: #Predicate { dogIDs.contains($0.id) })))
        let stored = byID(stored)
        var records = stored
        store(rows, over: stored) { downloaded in
            let row = downloaded.row
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

/// The GPS track of a downloaded walk did not download.
private struct MissingTrack: Error {
    var walk: UUID
}
