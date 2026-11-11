//
//  UploadingRow.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 07.10.2026.
//

import Foundation
import SwiftData

/// A row of the local store that uploads to the server.
public nonisolated protocol UploadingRow: PersistentModel {
    /// The stable ID of the row, which is the same on every phone.
    var id: UUID { get }
    /// Whether the row has changed since its last upload.
    var isWaitingToUpload: Bool { get set }
    /// The time of the last change on this phone.
    var changedAt: Date { get set }
    /// The time when the row was deleted, or nil. A deleted row stays, so
    /// that the other phones learn about the deletion.
    var deletedAt: Date? { get set }
}

extension UploadingRow {
    /// Notes a change of the row on this phone, so that the row uploads.
    public nonisolated func noteChange(at date: Date = .now) {
        isWaitingToUpload = true
        changedAt = date
    }

    /// Deletes the row. It stays in the store with the deletion time, so
    /// that the deletion uploads, and the app no longer shows it.
    public nonisolated func markDeleted(at date: Date = .now) {
        deletedAt = date
        noteChange(at: date)
    }
}

extension PersistentModel {
    /// Sets the value only when it differs, so that an unchanged row, for
    /// example a row that downloads again, makes no change to save.
    public nonisolated func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<Self, Value>, to value: Value) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    /// Sets the date only when it differs by a millisecond or more. The
    /// server keeps dates with milliseconds only, and the phone that wrote
    /// the date keeps it exactly, because the collections match a walk
    /// again when its start or end changes.
    public nonisolated func set(_ keyPath: ReferenceWritableKeyPath<Self, Date>, to value: Date) {
        if !self[keyPath: keyPath].isSameMillisecond(as: value) {
            self[keyPath: keyPath] = value
        }
    }

    public nonisolated func set(_ keyPath: ReferenceWritableKeyPath<Self, Date?>, to value: Date?) {
        switch (self[keyPath: keyPath], value) {
        case (nil, nil):
            return
        case let (stored?, value?) where stored.isSameMillisecond(as: value):
            return
        default:
            self[keyPath: keyPath] = value
        }
    }
}

extension Date {
    public nonisolated func isSameMillisecond(as other: Date) -> Bool {
        abs(timeIntervalSince(other)) < 0.001
    }
}
