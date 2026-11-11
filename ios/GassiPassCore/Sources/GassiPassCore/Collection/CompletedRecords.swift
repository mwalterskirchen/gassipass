//
//  CompletedRecords.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation

/// A permanent record that a dog has reached a goal on this date: it has
/// completed an area, a street or a ring, or it has reached a step of the
/// stamp of an area. The goal is the BFS number of an area, the ID of a
/// street, a `Ring` or an `AreaStepID`. A map release that later lowers the completion does not
/// remove it.
public nonisolated struct CompletedRecord<Dog: Hashable & Sendable, Goal: Hashable & Sendable>: Hashable, Sendable {
    public let dog: Dog
    public let goal: Goal
    public let date: Date

    public init(dog: Dog, goal: Goal, date: Date) {
        self.dog = dog
        self.goal = goal
        self.date = date
    }
}

nonisolated extension CollectionEngine {
    /// A new completed record for each dog and area that has no record yet
    /// and that the dog has completed, sorted by date. The existing records
    /// stay, as the engine never removes a record.
    public static func completedRecords<Dog>(
        collections: [Dog: DogCollection], areas: [Area], existing: [CompletedRecord<Dog, Area.ID>]
    ) -> [CompletedRecord<Dog, Area.ID>] {
        completedRecords(collections: collections, goals: areas, existing: existing)
    }

    /// A new completed record for each dog and street that has no record yet
    /// and that the dog has completed. The rules are the same as for areas.
    public static func completedRecords<Dog>(
        collections: [Dog: DogCollection], streets: [Street], existing: [CompletedRecord<Dog, Street.ID>]
    ) -> [CompletedRecord<Dog, Street.ID>] {
        completedRecords(collections: collections, goals: streets, existing: existing)
    }

    /// The date of a new record is the date of the segment whose collection
    /// completed the goal.
    private static func completedRecords<Dog, Goal: CompletionGoal>(
        collections: [Dog: DogCollection], goals: [Goal], existing: [CompletedRecord<Dog, Goal.ID>]
    ) -> [CompletedRecord<Dog, Goal.ID>] {
        let goalOf = Dictionary(goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recorded = Set(existing.map { DogGoal(dog: $0.dog, goal: $0.goal) })
        var new: [CompletedRecord<Dog, Goal.ID>] = []
        for (dog, collection) in collections {
            let segmentsByGoal = Dictionary(grouping: collection.collected.values, by: Goal.goal(of:))
            for (id, segments) in segmentsByGoal {
                // Only a goal that the dog has completed needs the segments
                // in the order of time.
                guard let id, let goal = goalOf[id], !recorded.contains(DogGoal(dog: dog, goal: id)),
                      goal.isCompleted(goal.completion(with: segments)),
                      let date = goal.firstDate(of: segments, where: goal.isCompleted)
                else { continue }
                new.append(CompletedRecord(dog: dog, goal: id, date: date))
            }
        }
        return new.sorted { $0.date < $1.date }
    }

    /// A new record for each dog and area step (`StampStep.areaSteps`) that
    /// the dog has reached and that has no record yet, sorted by date. The
    /// existing records stay.
    public static func stepRecords<Dog>(
        collections: [Dog: DogCollection], areas: [Area], existing: [CompletedRecord<Dog, AreaStepID>]
    ) -> [CompletedRecord<Dog, AreaStepID>] {
        let areaOf = Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recorded = Set(existing.map { DogGoal(dog: $0.dog, goal: $0.goal) })
        var new: [CompletedRecord<Dog, AreaStepID>] = []
        for (dog, collection) in collections {
            for (id, segments) in Dictionary(grouping: collection.collected.values, by: \.area) {
                guard let area = areaOf[id] else { continue }
                // Only a step that the dog has reached and that has no record
                // needs the segments in the order of time.
                let completion = area.completion(with: segments)
                let missing = StampStep.areaSteps.filter { step in
                    step.isReached(by: completion)
                        && !recorded.contains(DogGoal(dog: dog, goal: AreaStepID(area: id, step: step)))
                }
                guard !missing.isEmpty else { continue }
                for (step, date) in area.stepDates(of: segments, steps: missing) {
                    new.append(CompletedRecord(dog: dog, goal: AreaStepID(area: id, step: step), date: date))
                }
            }
        }
        return new.sorted { ($0.date, $0.goal.step) < ($1.date, $1.goal.step) }
    }

    /// The areas or streets that the newly collected segments completed,
    /// with the dogs that completed each one: the goals that were not
    /// completed before these segments and are completed with them. It does
    /// not know the records, so a goal that a dog completed before and that
    /// a map release reopened is also in the result.
    public static func completedGoals<Dog, Goal: CompletionGoal>(
        by newlyCollected: [Dog: Set<Segment.ID>], in collections: [Dog: DogCollection],
        goal: (Goal.ID) -> Goal?
    ) -> [Goal.ID: Set<Dog>] {
        var completed: [Goal.ID: Set<Dog>] = [:]
        for lift in lifts(by: newlyCollected, in: collections, goal: goal)
        where !lift.goal.isCompleted(lift.before) && lift.goal.isCompleted(lift.after) {
            completed[lift.goal.id, default: []].insert(lift.dog)
        }
        return completed
    }

    /// The steps of the area stamps that the newly collected segments
    /// reached, with the dogs that reached each one. The full stamp is the
    /// step `.completed`. Like `completedGoals`, it does not know the records.
    public static func reachedSteps<Dog>(
        by newlyCollected: [Dog: Set<Segment.ID>], in collections: [Dog: DogCollection],
        area: (Area.ID) -> Area?
    ) -> [AreaStepID: Set<Dog>] {
        var reached: [AreaStepID: Set<Dog>] = [:]
        for lift in lifts(by: newlyCollected, in: collections, goal: area) {
            for step in StampStep.allCases where !step.isReached(by: lift.before) && step.isReached(by: lift.after) {
                reached[AreaStepID(area: lift.goal.id, step: step), default: []].insert(lift.dog)
            }
        }
        return reached
    }

    /// The completion before and after the newly collected segments, of
    /// each dog and each goal that the segments belong to.
    private static func lifts<Dog, Goal: CompletionGoal>(
        by newlyCollected: [Dog: Set<Segment.ID>], in collections: [Dog: DogCollection],
        goal: (Goal.ID) -> Goal?
    ) -> [(dog: Dog, goal: Goal, before: Completion, after: Completion)] {
        var lifts: [(dog: Dog, goal: Goal, before: Completion, after: Completion)] = []
        for (dog, segments) in newlyCollected {
            guard let collection = collections[dog] else { continue }
            let touched = Set(segments.compactMap { collection.collected[$0].flatMap(Goal.goal(of:)) })
            for id in touched {
                guard let goal = goal(id) else { continue }
                let ofGoal = collection.collected.filter { Goal.goal(of: $0.value) == id }
                lifts.append((
                    dog: dog, goal: goal,
                    before: goal.completion(with: ofGoal.filter { !segments.contains($0.key) }.values),
                    after: goal.completion(with: ofGoal.values)))
            }
        }
        return lifts
    }

    /// The date on which the dog reached the goal, or nil if it has not.
    /// With two devices there can be two records for the same dog and goal,
    /// and the earliest date counts.
    public static func completedDate<Dog, Goal>(of goal: Goal, for dog: Dog, in records: [CompletedRecord<Dog, Goal>]) -> Date? {
        records.filter { $0.dog == dog && $0.goal == goal }.map(\.date).min()
    }

    private struct DogGoal<Dog: Hashable, Goal: Hashable>: Hashable {
        let dog: Dog
        let goal: Goal
    }
}
