//
//  SyncedRowTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

/// The rows of the synced tables (`SyncedRows.tables`): their order, their
/// columns and their mapping to the local rows. Each table needs samples
/// (`SampledRow`), so a new table gets these tests too.
@MainActor
struct SyncedRowTests {
    @Test func eachTableComesAfterTheTablesThatItsRowsPointTo() throws {
        let order = SyncedRows.tables.map { $0.table }
        for (index, table) in SyncedRows.tables.enumerated() {
            let sampled = try #require(table as? any SampledRow.Type, "\(table) has no samples")
            for target in sampled.targetTables {
                let targetIndex = try #require(order.firstIndex(of: target), "\(target) is no synced table")
                #expect(targetIndex < index, "\(table.table) points to \(target), which comes later")
            }
        }
    }

    /// An upload writes the whole row, so a column without a value must
    /// still be in the row, or the server keeps its old value.
    @Test func eachRowEncodesEveryColumnAlsoWithoutAValue() throws {
        for table in SyncedRows.tables {
            let sampled = try #require(table as? any SampledRow.Type, "\(table) has no samples")
            try checkColumns(of: sampled)
        }
    }

    @Test func eachRowKeepsEveryColumnOnTheWayToTheLocalRowAndBack() throws {
        for table in SyncedRows.tables {
            let sampled = try #require(table as? any SampledRow.Type, "\(table) has no samples")
            try checkLocalRow(of: sampled.full)
            try checkLocalRow(of: sampled.empty)
        }
    }

    private func checkColumns<Row: SampledRow>(of type: Row.Type) throws {
        #expect(try keys(of: Row.empty) == keys(of: Row.full), "\(Row.table)")
        let full = Row.full
        #expect(try JSONDecoder().decode(Row.self, from: JSONEncoder().encode(full)) == full, "\(Row.table)")
    }

    private func keys(of row: some Encodable) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row))
        return Set(try #require(object as? [String: Any]).keys)
    }

    /// Stores the row as a new local row, with its targets, and makes the
    /// row for the server from the local row again.
    private func checkLocalRow<Row: SampledRow>(of row: Row) throws {
        // The context does not keep the container.
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let pack = Pack(id: row.packID, name: "Rudel", createdAt: start)
        context.insert(pack)
        var targets: [UUID: any UploadingRow] = [:]
        for target in row.targets {
            targets[target.id] = try insert(target, in: context, pack: pack)
        }

        let local = try row.store(
            in: nil, targets: StoreTargets(pack: pack, rows: targets), changedAt: start, context: context)

        let filePath = Row.file.flatMap { row[keyPath: $0.path] }
        #expect(Row(local, packID: row.packID, filePath: filePath) == row, "\(Row.table)")
        #expect(Row.targets(of: local) == row.targets, "\(Row.table)")
        #expect(!local.isWaitingToUpload, "\(Row.table)")
    }

    private func insert(_ target: SyncedTarget, in context: ModelContext, pack: Pack) throws -> any UploadingRow {
        switch target.table {
        case .dogs:
            let dog = Dog(id: target.id, name: "Bello")
            dog.pack = pack
            context.insert(dog)
            return dog
        case .walks:
            let walk = Walk(id: target.id, startedAt: start)
            walk.endedAt = start + 3_600
            context.insert(walk)
            return walk
        default:
            throw UnknownTarget()
        }
    }

    private struct UnknownTarget: Error {}
}

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let pack = UUID()
private let dog = UUID()
private let walk = UUID()

/// A row of a synced table with every optional column set (`full`), and
/// with no optional column set (`empty`).
protocol SampledRow: SyncedRow, Equatable {
    static var full: Self { get }
    static var empty: Self { get }
}

extension SampledRow {
    /// The tables that the rows of the table point to.
    static var targetTables: [ServerTable] {
        full.targets.map(\.table)
    }
}

extension ServerDog: SampledRow {
    static var full: ServerDog {
        ServerDog(
            id: dog, packID: pack, name: "Bello", photoPath: "\(pack)/\(dog)-photo.jpg", retiredAt: start,
            retirementReason: "Alt", bornOn: WeekCalendar.date(ofDayText: "2019-05-17"), addedAt: start - 3_600,
            deletedAt: start + 60)
    }

    static var empty: ServerDog {
        ServerDog(
            id: dog, packID: pack, name: "Bello", photoPath: nil, retiredAt: nil, retirementReason: "", deletedAt: nil)
    }
}

extension ServerWalk: SampledRow {
    static var full: ServerWalk {
        ServerWalk(
            id: walk, packID: pack, startedAt: start, endedAt: start + 3_600, trackPath: "\(pack)/\(walk)",
            distanceMetres: 2_345.5, distanceVersion: 3, continuedAt: start + 1_800, deviceID: "device",
            memberName: "Anna", deletedAt: start + 7_200)
    }

    static var empty: ServerWalk {
        ServerWalk(
            id: walk, packID: pack, startedAt: start, endedAt: start + 3_600, trackPath: nil, distanceMetres: 0,
            distanceVersion: 0, continuedAt: nil, deviceID: "", memberName: "", deletedAt: nil)
    }
}

extension ServerWalkDog: SampledRow {
    static var full: ServerWalkDog {
        ServerWalkDog(id: UUID(), packID: pack, walkID: walk, dogID: dog, deletedAt: start)
    }

    static var empty: ServerWalkDog {
        ServerWalkDog(id: UUID(), packID: pack, walkID: walk, dogID: dog, deletedAt: nil)
    }
}

extension ServerCompletedArea: SampledRow {
    static var full: ServerCompletedArea {
        ServerCompletedArea(id: UUID(), packID: pack, dogID: dog, area: 243, completedAt: start, deletedAt: start + 60)
    }

    static var empty: ServerCompletedArea {
        ServerCompletedArea(id: UUID(), packID: pack, dogID: dog, area: 243, completedAt: start, deletedAt: nil)
    }
}

extension ServerCompletedStreet: SampledRow {
    static var full: ServerCompletedStreet {
        ServerCompletedStreet(
            id: UUID(), packID: pack, dogID: dog, area: 243, street: "Zürcherstrasse", completedAt: start,
            deletedAt: start + 60)
    }

    static var empty: ServerCompletedStreet {
        ServerCompletedStreet(
            id: UUID(), packID: pack, dogID: dog, area: 243, street: "Zürcherstrasse", completedAt: start,
            deletedAt: nil)
    }
}

extension ServerAreaStep: SampledRow {
    static var full: ServerAreaStep {
        ServerAreaStep(id: UUID(), packID: pack, dogID: dog, area: 243, step: 25, reachedAt: start, deletedAt: start + 60)
    }

    static var empty: ServerAreaStep {
        ServerAreaStep(id: UUID(), packID: pack, dogID: dog, area: 243, step: 0, reachedAt: start, deletedAt: nil)
    }
}

extension ServerCompletedRing: SampledRow {
    static var full: ServerCompletedRing {
        ServerCompletedRing(
            id: UUID(), packID: pack, dogID: dog, ring: 3, radiusMetres: 490, centreLatitude: 47.4,
            centreLongitude: 8.4, completedAt: start, deletedAt: start + 60)
    }

    static var empty: ServerCompletedRing {
        ServerCompletedRing(
            id: UUID(), packID: pack, dogID: dog, ring: 1, radiusMetres: 250, centreLatitude: 47.4,
            centreLongitude: 8.4, completedAt: start, deletedAt: nil)
    }
}

extension ServerGoalSet: SampledRow {
    /// The server keeps the week as its day, so the sample week starts at a
    /// Monday midnight in Zurich.
    private static var weekStart: Date {
        WeekCalendar.week(containing: start).start
    }

    static var full: ServerGoalSet {
        let slot = GoalSlotColumns(
            goal: GoalColumns(kind: "step", target: 25, area: 243, street: "Zürcherstrasse", ring: 3),
            finishedAt: start)
        return ServerGoalSet(
            id: UUID(), packID: pack, dogID: dog, weekStart: weekStart, slots: [slot, slot, slot], swappedSlot: 2,
            deletedAt: start + 60)
    }

    static var empty: ServerGoalSet {
        let slot = GoalSlotColumns(goal: GoalColumns(kind: "new_area"), finishedAt: nil)
        return ServerGoalSet(
            id: UUID(), packID: pack, dogID: dog, weekStart: weekStart, slots: [slot, slot, slot], swappedSlot: nil,
            deletedAt: nil)
    }
}
