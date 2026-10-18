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
/// weekly goals. `Account` runs it after
/// the pack of the phone is on the server.
///
/// A photo or GPS track uploads only when it has changed (`UploadedFiles`),
/// and the old file of the row then leaves the server. A row that uploads
/// stops waiting, unless it changed during the upload.
/// A row that fails to upload waits for the next upload, and the other rows
/// upload without it. A failure without a network stops the upload, because
/// every other request would fail too. The files upload four at a time
/// (`FileTransfers`), before the rows of their table. A row uploads only after the rows that it points to,
/// so the dogs of a walk wait for the walk and for the dogs, and a completed
/// record, an area step, a ring stamp or a set of weekly goals waits for its
/// dog.
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
        let steps = [
            uploadDogs, uploadWalks, uploadWalkDogs, uploadCompletedAreas, uploadCompletedStreets, uploadAreaSteps,
            uploadCompletedRings, uploadWeeklyGoals,
        ]
        for step in steps {
            do {
                try await step()
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

    private static let waitingDogs = FetchDescriptor<Dog>(predicate: #Predicate { $0.isWaitingToUpload })
    /// A walk that is still being recorded waits until it ends.
    private static let waitingEndedWalks = FetchDescriptor<Walk>(predicate: #Predicate {
        $0.isWaitingToUpload && $0.endedAt != nil
    })
    private static let waitingWalkDogs = FetchDescriptor<WalkDog>(predicate: #Predicate { $0.isWaitingToUpload })
    private static let waitingCompletedAreas = FetchDescriptor<CompletedArea>(predicate: #Predicate {
        $0.isWaitingToUpload
    })
    private static let waitingCompletedStreets = FetchDescriptor<CompletedStreet>(predicate: #Predicate {
        $0.isWaitingToUpload
    })
    private static let waitingAreaSteps = FetchDescriptor<AreaStep>(predicate: #Predicate { $0.isWaitingToUpload })
    private static let waitingCompletedRings = FetchDescriptor<CompletedRing>(predicate: #Predicate {
        $0.isWaitingToUpload
    })
    private static let waitingGoalSets = FetchDescriptor<StoredGoalSet>(predicate: #Predicate { $0.isWaitingToUpload })

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

    private func uploadDogs() async throws {
        // A dog that changes during the upload of its photo keeps waiting.
        let dogs = try context.fetch(Self.waitingDogs).map { (dog: $0, changedAt: $0.changedAt) }
        let packID = packID
        let photoPaths = try await uploadFiles(of: dogs.map { ($0.dog.id, $0.dog.photoData) }, in: .dogPhotos) {
            .dogPhoto(dog: $0, pack: packID, hash: $1)
        }
        var changes: [Change<Dog, ServerDog>] = []
        for (dog, changedAt) in dogs {
            // A dog whose photo failed to upload waits for the next upload.
            guard let photoPath = photoPaths[dog.id] else { continue }
            changes.append(Change(local: dog, changedAt: changedAt, row: ServerDog(
                id: dog.id, packID: packID, name: dog.name, photoPath: photoPath, retiredAt: dog.retiredAt,
                retirementReason: dog.retirementReason, deletedAt: dog.deletedAt)))
        }
        try await upload(changes, with: server.uploadDogs)
    }

    private func uploadWalks() async throws {
        let walks = try context.fetch(Self.waitingEndedWalks).map { (walk: $0, changedAt: $0.changedAt) }
        let packID = packID
        let trackPaths = try await uploadFiles(of: walks.map { ($0.walk.id, $0.walk.trackData) }, in: .tracks) {
            row, _ in .track(walk: row, pack: packID)
        }
        var changes: [Change<Walk, ServerWalk>] = []
        for (walk, changedAt) in walks {
            guard let endedAt = walk.endedAt, let trackPath = trackPaths[walk.id] else { continue }
            changes.append(Change(local: walk, changedAt: changedAt, row: ServerWalk(
                id: walk.id, packID: packID, startedAt: walk.startedAt, endedAt: endedAt, trackPath: trackPath,
                distanceMetres: walk.distanceMetres, distanceVersion: walk.distanceVersion,
                continuedAt: walk.continuedAt, deviceID: walk.deviceID, memberName: walk.memberName,
                deletedAt: walk.deletedAt)))
        }
        try await upload(changes, with: server.uploadWalks)
    }

    /// Uploads the dogs of the walks whose walk and dog are on the server.
    private func uploadWalkDogs() async throws {
        var changes: [Change<WalkDog, ServerWalkDog>] = []
        for walkDog in try context.fetch(Self.waitingWalkDogs) {
            guard let walk = walkDog.walk, let dog = walkDog.dog else {
                // It can never upload, so it stops waiting.
                walkDog.isWaitingToUpload = false
                continue
            }
            guard walk.endedAt != nil, !walk.isWaitingToUpload, !dog.isWaitingToUpload else { continue }
            changes.append(Change(local: walkDog, changedAt: walkDog.changedAt, row: ServerWalkDog(
                id: walkDog.id, packID: packID, walkID: walk.id, dogID: dog.id, deletedAt: walkDog.deletedAt)))
        }
        try await upload(changes, with: server.uploadWalkDogs)
    }

    private func uploadCompletedAreas() async throws {
        var changes: [Change<CompletedArea, ServerCompletedArea>] = []
        for record in try context.fetch(Self.waitingCompletedAreas) {
            guard let dog = dogOnServer(record.dog, of: record) else { continue }
            changes.append(Change(local: record, changedAt: record.changedAt, row: ServerCompletedArea(
                id: record.id, packID: packID, dogID: dog.id, area: record.area, completedAt: record.completedAt,
                deletedAt: record.deletedAt)))
        }
        try await upload(changes, with: server.uploadCompletedAreas)
    }

    private func uploadCompletedStreets() async throws {
        var changes: [Change<CompletedStreet, ServerCompletedStreet>] = []
        for record in try context.fetch(Self.waitingCompletedStreets) {
            guard let dog = dogOnServer(record.dog, of: record) else { continue }
            changes.append(Change(local: record, changedAt: record.changedAt, row: ServerCompletedStreet(
                id: record.id, packID: packID, dogID: dog.id, area: record.area, street: record.street,
                completedAt: record.completedAt, deletedAt: record.deletedAt)))
        }
        try await upload(changes, with: server.uploadCompletedStreets)
    }

    /// Uploads the area steps. An area step keeps the ID of its dog and no
    /// relationship (`LocalSchemaV3`), so it finds its dog by the ID.
    private func uploadAreaSteps() async throws {
        let steps = try context.fetch(Self.waitingAreaSteps)
        let dogIDs = Set(steps.map(\.dogID))
        let dogs = try context.fetch(FetchDescriptor<Dog>(predicate: #Predicate { dogIDs.contains($0.id) }))
        let dogByID = Dictionary(dogs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [Change<AreaStep, ServerAreaStep>] = []
        for step in steps {
            guard let dog = dogOnServer(dogByID[step.dogID], of: step) else { continue }
            changes.append(Change(local: step, changedAt: step.changedAt, row: ServerAreaStep(
                id: step.id, packID: packID, dogID: dog.id, area: step.area, step: step.step,
                reachedAt: step.reachedAt, deletedAt: step.deletedAt)))
        }
        try await upload(changes, with: server.uploadAreaSteps)
    }

    /// Uploads the ring stamps, which find their dog by its ID, like the
    /// area steps.
    private func uploadCompletedRings() async throws {
        let rings = try context.fetch(Self.waitingCompletedRings)
        let dogIDs = Set(rings.map(\.dogID))
        let dogs = try context.fetch(FetchDescriptor<Dog>(predicate: #Predicate { dogIDs.contains($0.id) }))
        let dogByID = Dictionary(dogs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [Change<CompletedRing, ServerCompletedRing>] = []
        for ring in rings {
            guard let dog = dogOnServer(dogByID[ring.dogID], of: ring) else { continue }
            changes.append(Change(local: ring, changedAt: ring.changedAt, row: ServerCompletedRing(
                id: ring.id, packID: packID, dogID: dog.id, ring: ring.number, radiusMetres: ring.radiusMetres,
                centreLatitude: ring.centreLatitude, centreLongitude: ring.centreLongitude,
                completedAt: ring.completedAt, deletedAt: ring.deletedAt)))
        }
        try await upload(changes, with: server.uploadCompletedRings)
    }

    /// Uploads the sets of weekly goals, which find their dog by its ID,
    /// like the area steps. The server refuses a second set for the same dog
    /// and week, which then waits until the download replaces it with the
    /// set of the server (`PackDownload`).
    private func uploadWeeklyGoals() async throws {
        let sets = try context.fetch(Self.waitingGoalSets)
        let dogIDs = Set(sets.map(\.dogID))
        let dogs = try context.fetch(FetchDescriptor<Dog>(predicate: #Predicate { dogIDs.contains($0.id) }))
        let dogByID = Dictionary(dogs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [Change<StoredGoalSet, ServerWeeklyGoals>] = []
        for set in sets {
            guard let dog = dogOnServer(dogByID[set.dogID], of: set) else { continue }
            changes.append(Change(local: set, changedAt: set.changedAt, row: ServerWeeklyGoals(
                id: set.id, packID: packID, dogID: dog.id, weekStart: set.weekStart, slots: set.columns,
                swappedSlot: set.swappedSlot, deletedAt: set.deletedAt)))
        }
        try await upload(changes, with: server.uploadWeeklyGoals)
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

    /// The dog of a completed record or an area step when the dog is on the
    /// server, or nil. A record without a dog can never upload, so it stops
    /// waiting.
    private func dogOnServer(_ dog: Dog?, of record: some UploadingRow) -> Dog? {
        guard let dog else {
            record.isWaitingToUpload = false
            return nil
        }
        return dog.isWaitingToUpload ? nil : dog
    }

    /// Sends the rows in batches, and notes after each batch that its rows
    /// have uploaded. When the server refuses a row of a batch, the rows of
    /// the batch upload one at a time, so that the refused row waits alone.
    /// Another failure, for example without a network, stops the upload.
    private func upload<LocalRow, Row>(
        _ changes: [Change<LocalRow, Row>], with send: ([Row]) async throws -> Void
    ) async throws {
        // A row that can never upload stopped waiting without an upload.
        if context.hasChanges {
            try context.save()
        }
        for start in stride(from: 0, to: changes.count, by: Self.batchSize) {
            let batch = changes[start..<min(start + Self.batchSize, changes.count)]
            do {
                try await send(batch.map(\.row))
                try markUploaded(batch)
            } catch is RowRefused where batch.count > 1 {
                for change in batch {
                    if await attempt({ try await send([change.row]) }) {
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
