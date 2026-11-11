//
//  Collections+Records.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import SwiftData

/// The permanent records that an update stores: the completed areas and
/// streets, the area steps and the ring stamps (ADR 0002).
extension Collections {
    /// The area steps of the dog, with each area that the dog has completed
    /// as the step `.completed`. The store keeps a completed area apart from
    /// the other steps of its stamp.
    func stampRecords(of dog: Dog) -> [CompletedRecord<UUID, AreaStepID>] {
        stepRecords(of: dog.id) + dog.completedAreaRecords.map {
            CompletedRecord(dog: dog.id, goal: AreaStepID(area: $0.goal, step: .completed), date: $0.date)
        }
    }

    /// Stores a record for each dog and area or street that the dog has
    /// completed, and for each area step that the dog has reached, that has
    /// no record yet, and merges the records that were stored for the same
    /// dog and goal. It returns the new records of completed areas.
    func recordCompleted(dogs: [Dog]) throws -> [CompletedRecord<UUID, Area.ID>] {
        let steps = try context.fetch(Self.shownAreaSteps)
        // Both merges run, also when the first one deletes a record.
        let deletedRecords = mergeRecords(of: dogs)
        let deletedDuplicates = mergeSteps(steps) || deletedRecords
        let dogByID = Dictionary(dogs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let areaRecords = CollectionEngine.completedRecords(
            collections: byDog, areas: Array(areas.values), existing: dogs.flatMap(\.completedAreaRecords))
        for record in areaRecords {
            guard let dog = dogByID[record.dog] else { continue }
            _ = CompletedArea(dog: dog, area: record.goal, completedAt: record.date, context: context)
        }

        let streetRecords = CollectionEngine.completedRecords(
            collections: byDog, streets: streets.values.flatMap { $0 }, existing: dogs.flatMap(\.completedStreetRecords))
        for record in streetRecords {
            guard let dog = dogByID[record.dog] else { continue }
            _ = CompletedStreet(dog: dog, street: record.goal, completedAt: record.date, context: context)
        }

        // A record of a deleted dog does not count.
        let existingSteps = Self.records(of: steps.filter { $0.deletedAt == nil && dogByID[$0.dogID] != nil })
        let stepRecords = CollectionEngine.stepRecords(
            collections: byDog, areas: Array(areas.values), existing: existingSteps)
        for record in stepRecords {
            guard let dog = dogByID[record.dog] else { continue }
            _ = AreaStep(
                dog: dog, area: record.goal.area, step: record.goal.step, reachedAt: record.date, context: context)
        }

        // A completed record is permanent (ADR 0002).
        if deletedDuplicates || !areaRecords.isEmpty || !streetRecords.isEmpty || !stepRecords.isEmpty {
            try context.save()
        }
        self.stepRecords = existingSteps + stepRecords
        return areaRecords
    }

    /// Stores a ring stamp for each dog and ring around the home base that
    /// the dog has completed and that has no stamp yet, and merges the
    /// stamps that were stored for the same dog and ring. It loads the
    /// segments up to the ring after the current ring of each dog, also
    /// after a new stamp.
    func recordRings(dogs: [Dog]) async throws {
        let rows = try context.fetch(Self.shownRings)
        let deletedDuplicates = mergeRings(rows)
        let dogIDs = Set(dogs.map(\.id))
        var records = Self.ringRecords(of: rows, dogs: dogIDs)
        let homeBase = try Pack.ofThisPhone(in: context)?.homeBase
        var newRecords: [CompletedRecord<UUID, Ring>] = []
        if let homeBase {
            let collections = byDog.filter { dogIDs.contains($0.key) }
            while true {
                let outermost = dogIDs
                    .map {
                        CollectionEngine.currentRing(
                            of: $0, around: homeBase, records: records, skippingEmptyIn: ringSegments)
                    }
                    .max { $0.number < $1.number } ?? Ring(number: 1, centre: homeBase)
                if ringSegments?.holds(outermost.next) != true {
                    let loaded = try await matcher.ringSegments(
                        around: homeBase, withinMetres: outermost.next.radiusMetres)
                    try Task.checkCancellation()
                    ringSegments = loaded
                    // The new segments can skip an empty ring, which moves
                    // the current ring out.
                    continue
                }
                guard let ringSegments else { break }
                let new = CollectionEngine.ringRecords(collections: collections, around: ringSegments, existing: records)
                guard !new.isEmpty else { break }
                records += new
                newRecords += new
            }
        }
        for record in newRecords {
            _ = CompletedRing(dogID: record.dog, ring: record.goal, completedAt: record.date, context: context)
        }
        // A ring stamp is permanent (ADR 0002).
        if deletedDuplicates || !newRecords.isEmpty {
            try context.save()
        }
        self.homeBase = homeBase
        ringRecords = records
    }

    /// The ring stamps that are not deleted.
    static let shownRings = FetchDescriptor<CompletedRing>(predicate: #Predicate { $0.deletedAt == nil })

    /// The records of the ring stamps of the dogs that are not deleted, and
    /// of two stamps of the same dog and ring only the one that
    /// `mergeRings(_:)` keeps.
    static func ringRecords(of rows: [CompletedRing], dogs: Set<UUID>) -> [CompletedRecord<UUID, Ring>] {
        let shown = rows.filter { $0.deletedAt == nil && dogs.contains($0.dogID) }
        return Dictionary(grouping: shown) { RingKey(dog: $0.dogID, ring: $0.ring) }.values
            .compactMap { $0.min { ($0.completedAt, $0.id.uuidString) < ($1.completedAt, $1.id.uuidString) }?.record }
    }

    /// Keeps the earliest of the ring stamps that were stored for the same
    /// dog and ring, like `mergeRecords(of:)`. It returns whether it deleted
    /// a stamp.
    private func mergeRings(_ rings: [CompletedRing]) -> Bool {
        let groups = Dictionary(grouping: rings) { RingKey(dog: $0.dogID, ring: $0.ring) }
        return deleteAllButEarliest(groups.values, order: { ($0.completedAt, $0.id.uuidString) })
    }

    /// The area steps that are not deleted.
    static let shownAreaSteps = FetchDescriptor<AreaStep>(predicate: #Predicate { $0.deletedAt == nil })

    /// The records of the area steps with a step that this build knows.
    static func records(of steps: [AreaStep]) -> [CompletedRecord<UUID, AreaStepID>] {
        steps.compactMap { step in
            step.stampStep.map {
                CompletedRecord(dog: step.dogID, goal: AreaStepID(area: step.area, step: $0), date: step.reachedAt)
            }
        }
    }

    /// Keeps the earliest of the area steps that were stored for the same
    /// dog, area and step, like `mergeRecords(of:)`. It returns whether it
    /// deleted a step.
    private func mergeSteps(_ steps: [AreaStep]) -> Bool {
        let groups = Dictionary(grouping: steps) { StepKey(dog: $0.dogID, area: $0.area, step: $0.step) }
        return deleteAllButEarliest(groups.values, order: { ($0.reachedAt, $0.id.uuidString) })
    }

    /// Two phones can each store a record for the same dog and area or
    /// street before the records of one phone reach the other. This keeps
    /// the record with the earliest date and deletes the others. It returns
    /// whether it deleted a record.
    private func mergeRecords(of dogs: [Dog]) -> Bool {
        var deleted = false
        for dog in dogs {
            let areas = Dictionary(grouping: dog.shownCompletedAreas, by: \.area)
            deleted = deleteAllButEarliest(areas.values, order: { ($0.completedAt, $0.id.uuidString) }) || deleted
            let streets = Dictionary(grouping: dog.shownCompletedStreets, by: \.streetID)
            deleted = deleteAllButEarliest(streets.values, order: { ($0.completedAt, $0.id.uuidString) }) || deleted
        }
        return deleted
    }

    /// Deletes all records of each group but the first in the order. The
    /// order must be the same on every phone, or two phones could each
    /// keep a different record, and both records would then be deleted.
    private func deleteAllButEarliest<Record: UploadingRow>(
        _ groups: some Sequence<[Record]>, order: (Record) -> (Date, String)
    ) -> Bool {
        var deleted = false
        for records in groups where records.count > 1 {
            let earliest = records.min { order($0) < order($1) }
            for record in records where record !== earliest {
                record.markDeleted()
                deleted = true
            }
        }
        return deleted
    }
}

extension Dog {
    /// The completed records of the areas of the dog that are not deleted.
    /// They come from the relationship, which changes at once when a record
    /// is inserted.
    fileprivate var shownCompletedAreas: [CompletedArea] {
        (completedAreas ?? []).filter { $0.deletedAt == nil }
    }

    fileprivate var shownCompletedStreets: [CompletedStreet] {
        (completedStreets ?? []).filter { $0.deletedAt == nil }
    }

    /// The stored completed records of the areas of the dog.
    public var completedAreaRecords: [CompletedRecord<UUID, Area.ID>] {
        shownCompletedAreas.map {
            CompletedRecord(dog: id, goal: $0.area, date: $0.completedAt)
        }
    }

    /// The stored completed records of the streets of the dog.
    public var completedStreetRecords: [CompletedRecord<UUID, Street.ID>] {
        shownCompletedStreets.map {
            CompletedRecord(dog: id, goal: $0.streetID, date: $0.completedAt)
        }
    }
}

/// The area steps of one dog, area and step, of which only one stays.
private struct StepKey: Hashable {
    let dog: UUID
    let area: Area.ID
    let step: Int
}

/// The ring stamps of one dog and ring, of which only one stays.
private struct RingKey: Hashable {
    let dog: UUID
    let ring: Ring
}
