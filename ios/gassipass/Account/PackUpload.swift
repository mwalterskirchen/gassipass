//
//  PackUpload.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Foundation
import SwiftData

/// Uploads the rows of the pack that wait to upload (ADR 0006): the dogs
/// with their photos, the ended walks with their GPS tracks, the dogs of the
/// walks, and the completed records. `Account` runs it after the pack of the
/// phone is on the server.
///
/// A photo or GPS track uploads only when it has changed (`UploadedFiles`).
/// A row that uploads stops waiting, unless it changed during the upload.
/// A row that fails to upload waits for the next upload, and the other rows
/// upload without it. A row uploads only after the rows that it points to,
/// so the dogs of a walk wait for the walk and for the dogs, and a completed
/// record waits for its dog.
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
    /// tried every row.
    func run() async throws {
        defer {
            uploadedFiles.save()
        }
        await attempt(uploadDogs)
        await attempt(uploadWalks)
        await attempt(uploadWalkDogs)
        await attempt(uploadCompletedAreas)
        await attempt(uploadCompletedStreets)
        if let failure {
            throw failure
        }
    }

    /// The number of rows that wait to upload. A walk that is still being
    /// recorded, and its dogs, do not count, because they upload only after
    /// the walk ends.
    static func waitingRows(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Pack>(predicate: #Predicate { $0.isWaitingToUpload }))
            + context.fetchCount(waitingDogs)
            + context.fetchCount(waitingEndedWalks)
            + context.fetch(waitingWalkDogs).count { $0.walk?.endedAt != nil }
            + context.fetchCount(waitingCompletedAreas)
            + context.fetchCount(waitingCompletedStreets)
    }

    /// Whether a row that waits to upload changed in the interval. Like
    /// `waitingRows(in:)`, it leaves out a walk that is still being recorded.
    /// A change after the end of the interval does not count, so a row with a
    /// change time in the future, for example after the clock went back,
    /// does not start upload after upload.
    static func hasChanges(between start: Date, and end: Date, in context: ModelContext) throws -> Bool {
        let walkDogs = try context.fetch(FetchDescriptor<WalkDog>(predicate: #Predicate {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        }))
        return try context.fetchCount(FetchDescriptor<Pack>(predicate: #Predicate {
            $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
        })) > 0
            || context.fetchCount(FetchDescriptor<Dog>(predicate: #Predicate {
                $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
            })) > 0
            || context.fetchCount(FetchDescriptor<Walk>(predicate: #Predicate {
                $0.isWaitingToUpload && $0.endedAt != nil && $0.changedAt > start && $0.changedAt <= end
            })) > 0
            || walkDogs.contains { $0.walk?.endedAt != nil }
            || context.fetchCount(FetchDescriptor<CompletedArea>(predicate: #Predicate {
                $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
            })) > 0
            || context.fetchCount(FetchDescriptor<CompletedStreet>(predicate: #Predicate {
                $0.isWaitingToUpload && $0.changedAt > start && $0.changedAt <= end
            })) > 0
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

    /// Runs the step, and keeps its failure. It returns whether the step
    /// succeeded.
    @discardableResult
    private func attempt(_ step: () async throws -> Void) async -> Bool {
        do {
            try await step()
            return true
        } catch {
            failure = failure ?? error
            return false
        }
    }

    private func uploadDogs() async throws {
        var changes: [Change<Dog, ServerDog>] = []
        for dog in try context.fetch(Self.waitingDogs) {
            let changedAt = dog.changedAt
            let file = ServerFile.dogPhoto(dog: dog.id, pack: packID)
            guard await attempt({ try await self.upload(dog.photoData, to: file) }) else { continue }
            let photoPath = dog.photoData == nil ? nil : file.path
            changes.append(Change(local: dog, changedAt: changedAt, row: ServerDog(
                id: dog.id, packID: packID, name: dog.name, photoPath: photoPath, retiredAt: dog.retiredAt,
                retirementReason: dog.retirementReason, deletedAt: dog.deletedAt)))
        }
        try await upload(changes, with: server.uploadDogs)
    }

    private func uploadWalks() async throws {
        var changes: [Change<Walk, ServerWalk>] = []
        for walk in try context.fetch(Self.waitingEndedWalks) {
            guard let endedAt = walk.endedAt else { continue }
            let changedAt = walk.changedAt
            let file = ServerFile.track(walk: walk.id, pack: packID)
            // A deleted walk takes its GPS track off the server, so that
            // nobody can read the route any more.
            let track = walk.deletedAt == nil ? walk.trackData : nil
            guard await attempt({ try await self.upload(track, to: file) }) else { continue }
            let trackPath = track == nil ? nil : file.path
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

    /// Uploads the file when it has changed since its last upload, or
    /// deletes it from the server when the phone no longer has it.
    private func upload(_ data: Data?, to file: ServerFile) async throws {
        if let data {
            guard !uploadedFiles.contains(data, at: file) else { return }
            try await server.uploadFile(data, to: file)
            uploadedFiles.noteUploaded(data, at: file)
        } else {
            guard uploadedFiles.contains(file) else { return }
            try await server.deleteFile(file)
            uploadedFiles.noteDeleted(file)
        }
    }

    /// The dog of a completed record when the dog is on the server, or nil.
    /// A record without a dog can never upload, so it stops waiting.
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
