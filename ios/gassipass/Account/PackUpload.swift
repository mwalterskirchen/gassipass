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
/// walks, and the completed records. `Account` runs it after the pack of the phone is on the
/// server.
///
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
    /// The first failure of this upload.
    private var failure: (any Error)?

    init(context: ModelContext, server: any Server, packID: UUID) {
        self.context = context
        self.server = server
        self.packID = packID
    }

    /// Uploads the waiting rows. It throws the first failure after it has
    /// tried every row.
    func run() async throws {
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
        let walkDogs = try context.fetch(FetchDescriptor<WalkDog>(predicate: #Predicate { $0.isWaitingToUpload }))
        return try context.fetchCount(FetchDescriptor<Pack>(predicate: #Predicate { $0.isWaitingToUpload }))
            + context.fetchCount(FetchDescriptor<Dog>(predicate: #Predicate { $0.isWaitingToUpload }))
            + context.fetchCount(FetchDescriptor<Walk>(predicate: #Predicate {
                $0.isWaitingToUpload && $0.endedAt != nil
            }))
            + walkDogs.count { $0.walk?.endedAt != nil && $0.dog != nil }
            + context.fetchCount(FetchDescriptor<CompletedArea>(predicate: #Predicate {
                $0.isWaitingToUpload && $0.dog != nil
            }))
            + context.fetchCount(FetchDescriptor<CompletedStreet>(predicate: #Predicate {
                $0.isWaitingToUpload && $0.dog != nil
            }))
    }

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
        let dogs = try context.fetch(FetchDescriptor<Dog>(predicate: #Predicate { $0.isWaitingToUpload }))
        let changes = dogs.map { ($0, $0.changedAt) }
        var uploaded: [(Dog, Date)] = []
        var rows: [ServerDog] = []
        for (dog, changedAt) in changes {
            var photoPath: String?
            if let photo = dog.photoData {
                let file = ServerFile.dogPhoto(dog: dog.id, pack: packID)
                guard await attempt({ try await server.uploadFile(photo, to: file) }) else { continue }
                photoPath = file.path
            }
            rows.append(ServerDog(
                id: dog.id, packID: packID, name: dog.name, photoPath: photoPath, retiredAt: dog.retiredAt,
                retirementReason: dog.retirementReason, deletedAt: dog.deletedAt))
            uploaded.append((dog, changedAt))
        }
        try await upload(rows, of: uploaded, with: server.uploadDogs)
    }

    /// Uploads the ended walks. A walk that is still being recorded waits
    /// until it ends.
    private func uploadWalks() async throws {
        let walks = try context.fetch(FetchDescriptor<Walk>(predicate: #Predicate {
            $0.isWaitingToUpload && $0.endedAt != nil
        }))
        let changes = walks.map { ($0, $0.changedAt) }
        var uploaded: [(Walk, Date)] = []
        var rows: [ServerWalk] = []
        for (walk, changedAt) in changes {
            guard let endedAt = walk.endedAt else { continue }
            var trackPath: String?
            if let track = walk.trackData {
                let file = ServerFile.track(walk: walk.id, pack: packID)
                guard await attempt({ try await server.uploadFile(track, to: file) }) else { continue }
                trackPath = file.path
            }
            rows.append(ServerWalk(
                id: walk.id, packID: packID, startedAt: walk.startedAt, endedAt: endedAt, trackPath: trackPath,
                distanceMetres: walk.distanceMetres, distanceVersion: walk.distanceVersion,
                continuedAt: walk.continuedAt, deviceID: walk.deviceID, memberName: walk.memberName,
                deletedAt: walk.deletedAt))
            uploaded.append((walk, changedAt))
        }
        try await upload(rows, of: uploaded, with: server.uploadWalks)
    }

    /// Uploads the dogs of the walks whose walk and dog are on the server.
    private func uploadWalkDogs() async throws {
        let walkDogs = try context.fetch(FetchDescriptor<WalkDog>(predicate: #Predicate { $0.isWaitingToUpload }))
        var uploaded: [(WalkDog, Date)] = []
        var rows: [ServerWalkDog] = []
        for walkDog in walkDogs {
            guard let walk = walkDog.walk, let dog = walkDog.dog else {
                // It can never upload, so it stops waiting.
                walkDog.isWaitingToUpload = false
                continue
            }
            guard walk.endedAt != nil, !walk.isWaitingToUpload, !dog.isWaitingToUpload else { continue }
            rows.append(ServerWalkDog(
                id: walkDog.id, packID: packID, walkID: walk.id, dogID: dog.id, deletedAt: walkDog.deletedAt))
            uploaded.append((walkDog, walkDog.changedAt))
        }
        try await upload(rows, of: uploaded, with: server.uploadWalkDogs)
    }

    private func uploadCompletedAreas() async throws {
        let records = try context.fetch(FetchDescriptor<CompletedArea>(predicate: #Predicate { $0.isWaitingToUpload }))
        var uploaded: [(CompletedArea, Date)] = []
        var rows: [ServerCompletedArea] = []
        for record in records {
            guard let dog = uploadedDog(of: record, dog: record.dog) else { continue }
            rows.append(ServerCompletedArea(
                id: record.id, packID: packID, dogID: dog.id, area: record.area, completedAt: record.completedAt,
                deletedAt: record.deletedAt))
            uploaded.append((record, record.changedAt))
        }
        try await upload(rows, of: uploaded, with: server.uploadCompletedAreas)
    }

    private func uploadCompletedStreets() async throws {
        let records = try context.fetch(FetchDescriptor<CompletedStreet>(predicate: #Predicate { $0.isWaitingToUpload }))
        var uploaded: [(CompletedStreet, Date)] = []
        var rows: [ServerCompletedStreet] = []
        for record in records {
            guard let dog = uploadedDog(of: record, dog: record.dog) else { continue }
            rows.append(ServerCompletedStreet(
                id: record.id, packID: packID, dogID: dog.id, area: record.area, street: record.street,
                completedAt: record.completedAt, deletedAt: record.deletedAt))
            uploaded.append((record, record.changedAt))
        }
        try await upload(rows, of: uploaded, with: server.uploadCompletedStreets)
    }

    /// The dog of the record when the dog is on the server, or nil. A record
    /// without a dog can never upload, so it stops waiting.
    private func uploadedDog(of record: some UploadingRow, dog: Dog?) -> Dog? {
        guard let dog else {
            record.isWaitingToUpload = false
            return nil
        }
        return dog.isWaitingToUpload ? nil : dog
    }

    /// Sends the rows in batches, and notes after each batch that its rows
    /// have uploaded.
    private func upload<Row, LocalRow: UploadingRow>(
        _ rows: [Row], of uploaded: [(LocalRow, Date)], with send: ([Row]) async throws -> Void
    ) async throws {
        for start in stride(from: 0, to: rows.count, by: Self.batchSize) {
            let end = min(start + Self.batchSize, rows.count)
            try await send(Array(rows[start..<end]))
            try markUploaded(uploaded[start..<end])
        }
        // A row that can never upload stopped waiting without an upload.
        if context.hasChanges {
            try context.save()
        }
    }

    /// The number of rows in one request.
    private static let batchSize = 100

    /// Notes that the rows have uploaded, and saves. A row that changed
    /// since the upload started keeps waiting.
    private func markUploaded(_ uploaded: ArraySlice<(some UploadingRow, Date)>) throws {
        for (row, changedAt) in uploaded where row.changedAt == changedAt {
            row.isWaitingToUpload = false
        }
        if context.hasChanges {
            try context.save()
        }
    }
}
