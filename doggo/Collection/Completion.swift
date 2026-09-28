//
//  Completion.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation

/// The collected length of an area or a street as a share of its total
/// length, for one dog, and the number of collected segments.
nonisolated struct Completion: Equatable, Sendable {
    let collectedLengthMetres: Double
    let lengthMetres: Double
    let collectedSegmentCount: Int
    let segmentCount: Int

    /// The completion from 0 to 1.
    var share: Double {
        lengthMetres > 0 ? collectedLengthMetres / lengthMetres : 0
    }
}

/// An area or a street: a goal with a completion and completed records.
nonisolated protocol CompletionGoal: Identifiable, Sendable where ID: Sendable {
    var segmentCount: Int { get }
    var lengthMetres: Double { get }
    /// The goal of this kind that a collected segment belongs to, if any.
    static func goal(of segment: CollectedSegment) -> ID?
}

nonisolated extension Area: CompletionGoal {
    static func goal(of segment: CollectedSegment) -> Int? { segment.area }
}

nonisolated extension Street: CompletionGoal {
    static func goal(of segment: CollectedSegment) -> ID? { segment.street }
}

nonisolated extension DogCollection {
    /// The completion of an area for this dog.
    func completion(of area: Area) -> Completion {
        completions(of: [area])[area.id]!
    }

    /// The completion of each of the areas or streets for this dog, by the
    /// ID of the goal. For an area, the ID is the BFS number.
    func completions<Goal: CompletionGoal>(of goals: [Goal]) -> [Goal.ID: Completion] {
        let collectedByGoal = Dictionary(grouping: collected.values, by: Goal.goal(of:))
        return Dictionary(goals.map { goal in
            let segments = collectedByGoal[goal.id] ?? []
            return (goal.id, Completion(
                collectedLengthMetres: segments.reduce(0) { $0 + $1.lengthMetres },
                lengthMetres: goal.lengthMetres,
                collectedSegmentCount: segments.count,
                segmentCount: goal.segmentCount))
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The feature IDs of the collected segments of each area, by BFS
    /// number. An area with no collected segment has no entry.
    var collectedFeaturesByArea: [Area.ID: Set<Int>] {
        collected.values.reduce(into: [:]) { result, segment in
            result[segment.area, default: []].insert(segment.fid)
        }
    }
}

/// A permanent record that a dog has completed a goal: its completion
/// reached 100% on this date. The goal is the BFS number of an area or the
/// ID of a street. A map release that later lowers the completion does not
/// remove it.
nonisolated struct CompletedRecord<Dog: Hashable & Sendable, Goal: Hashable & Sendable>: Hashable, Sendable {
    let dog: Dog
    let goal: Goal
    let date: Date
}

nonisolated extension CollectionEngine {
    /// The existing completed records of areas, followed by a new record for
    /// each dog and area that has none yet and whose completion is 100%. The
    /// engine never removes a record.
    static func completedRecords<Dog>(
        collections: [Dog: DogCollection], areas: [Area], existing: [CompletedRecord<Dog, Area.ID>]
    ) -> [CompletedRecord<Dog, Area.ID>] {
        completedRecords(collections: collections, goals: areas, existing: existing)
    }

    /// The existing completed records of streets, followed by a new record
    /// for each dog and street that has none yet and whose completion is
    /// 100%. The rules are the same as for areas.
    static func completedRecords<Dog>(
        collections: [Dog: DogCollection], streets: [Street], existing: [CompletedRecord<Dog, Street.ID>]
    ) -> [CompletedRecord<Dog, Street.ID>] {
        completedRecords(collections: collections, goals: streets, existing: existing)
    }

    /// The completion of a goal reaches 100% when its last segment is
    /// collected, so the date of a new record is the latest date on which a
    /// segment of the goal was collected.
    private static func completedRecords<Dog, Goal: CompletionGoal>(
        collections: [Dog: DogCollection], goals: [Goal], existing: [CompletedRecord<Dog, Goal.ID>]
    ) -> [CompletedRecord<Dog, Goal.ID>] {
        let segmentCountOf = Dictionary(goals.map { ($0.id, $0.segmentCount) }, uniquingKeysWith: { first, _ in first })
        let recorded = Set(existing.map { DogGoal(dog: $0.dog, goal: $0.goal) })
        var new: [CompletedRecord<Dog, Goal.ID>] = []
        for (dog, collection) in collections {
            let segmentsByGoal = Dictionary(grouping: collection.collected.values, by: Goal.goal(of:))
            for (goal, segments) in segmentsByGoal {
                guard let goal, segments.count == segmentCountOf[goal],
                      !recorded.contains(DogGoal(dog: dog, goal: goal)),
                      let date = segments.map(\.collectedAt).max()
                else { continue }
                new.append(CompletedRecord(dog: dog, goal: goal, date: date))
            }
        }
        return existing + new.sorted { $0.date < $1.date }
    }

    /// The date on which the dog completed the area or street, or nil if it
    /// has not. With two devices there can be two records for the same dog
    /// and goal, and the earliest date counts.
    static func completedDate<Dog, Goal>(of goal: Goal, for dog: Dog, in records: [CompletedRecord<Dog, Goal>]) -> Date? {
        records.filter { $0.dog == dog && $0.goal == goal }.map(\.date).min()
    }

    private struct DogGoal<Dog: Hashable, Goal: Hashable>: Hashable {
        let dog: Dog
        let goal: Goal
    }
}
