//
//  LiveGoals.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation

/// The weekly goals of the dogs on the current walk, which the walk can
/// finish as it goes. Each goal reports once, when the walk finishes it. A
/// goal that is finished before the walk does not report.
nonisolated struct LiveGoals: Sendable {
    /// What a dog brings to the walk: its set of the week of the walk, its
    /// other ended walks, its collection before the walk and its stamps.
    struct Dog: Sendable {
        let id: UUID
        let set: WeeklyGoalSet
        let walks: [GoalWalk]
        let records: GoalRecords
    }

    /// A goal of a dog that the walk finished.
    struct Finished: Equatable, Sendable {
        let dog: UUID
        let goal: WeeklyGoal
    }

    private let dogs: [Dog]
    private let walkID: UUID
    private let startedAt: Date
    /// The slots of each dog that are finished, before or on the walk.
    private var finished: [UUID: Set<Int>] = [:]

    /// - Parameter collections: The collections of the dogs before the walk.
    init(dogs: [Dog], walkID: UUID, startedAt: Date, collections: [UUID: DogCollection]) {
        self.dogs = dogs
        self.walkID = walkID
        self.startedAt = startedAt
        for dog in dogs {
            let events = GoalEvents(
                week: dog.set.week, collection: collections[dog.id] ?? DogCollection(), walks: dog.walks,
                records: dog.records)
            finished[dog.id] = Set(dog.set.slots.indices.filter { index in
                dog.set.slots[index].finishedAt != nil
                    || WeeklyGoals.progress(of: dog.set.slots[index].goal, in: events).finishedAt != nil
            })
        }
    }

    /// The goals that the walk has finished since the last call.
    ///
    /// - Parameters:
    ///   - collections: The collections of the dogs with the walk so far.
    ///   - marks: The collected segments whose marks the walk refreshed, for
    ///     each dog, with the time of each mark.
    ///   - records: The stamps that the dogs earned on the walk.
    ///   - distanceMetres: The distance of the walk so far.
    mutating func finishedGoals(
        collections: [UUID: DogCollection], marks: [UUID: [Segment.ID: Date]], records: [UUID: GoalRecords],
        distanceMetres: Double, at now: Date
    ) -> [Finished] {
        var new: [Finished] = []
        for dog in dogs where finished[dog.id, default: []].count < dog.set.slots.count {
            let walk = GoalWalk(
                id: walkID, startedAt: startedAt, endedAt: max(now, startedAt), distanceMetres: distanceMetres,
                marks: marks[dog.id] ?? [:])
            let onWalk = records[dog.id] ?? GoalRecords()
            let events = GoalEvents(
                week: dog.set.week, collection: collections[dog.id] ?? DogCollection(), walks: dog.walks + [walk],
                records: GoalRecords(
                    streets: dog.records.streets + onWalk.streets, steps: dog.records.steps + onWalk.steps,
                    rings: dog.records.rings + onWalk.rings))
            for (index, slot) in dog.set.slots.enumerated() where !finished[dog.id, default: []].contains(index) {
                guard WeeklyGoals.progress(of: slot.goal, in: events).finishedAt != nil else { continue }
                finished[dog.id, default: []].insert(index)
                new.append(Finished(dog: dog.id, goal: slot.goal))
            }
        }
        return new
    }
}
