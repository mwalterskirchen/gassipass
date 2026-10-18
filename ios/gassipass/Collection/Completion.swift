//
//  Completion.swift
//  gassipass
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

    /// The completion from 0 to 1. It is exactly 1 when all segments are
    /// collected, because the sum of their lengths can end a little below
    /// the total length.
    var share: Double {
        if segmentCount > 0, collectedSegmentCount == segmentCount { return 1 }
        return lengthMetres > 0 ? collectedLengthMetres / lengthMetres : 0
    }
}

/// The number and the total length of the segments of an area, a street or
/// a ring, which a completion is a share of.
nonisolated protocol CompletionTotals: Sendable {
    var segmentCount: Int { get }
    var lengthMetres: Double { get }
}

/// An area or a street: a goal with a completion and completed records.
nonisolated protocol CompletionGoal: CompletionTotals, Identifiable where ID: Sendable {
    /// The goal of this kind that a collected segment belongs to, if any.
    static func goal(of segment: CollectedSegment) -> ID?
    /// Whether a dog with the completion has completed the goal.
    func isCompleted(_ completion: Completion) -> Bool
}

nonisolated extension Area: CompletionGoal {
    static func goal(of segment: CollectedSegment) -> Int? { segment.area }

    /// An area is completed at 95% (`CollectionRules.completedShare`).
    func isCompleted(_ completion: Completion) -> Bool {
        StampStep.completed.isReached(by: completion)
    }
}

nonisolated extension Street: CompletionGoal {
    static func goal(of segment: CollectedSegment) -> ID? { segment.street }

    /// A street is completed when every segment is collected.
    func isCompleted(_ completion: Completion) -> Bool {
        completion.segmentCount > 0 && completion.collectedSegmentCount == completion.segmentCount
    }
}

nonisolated extension CompletionTotals {
    /// The completion of the goal with the collected segments, which must
    /// all belong to the goal.
    func completion(with segments: some Collection<CollectedSegment>) -> Completion {
        Completion(
            collectedLengthMetres: segments.reduce(0) { $0 + $1.lengthMetres },
            lengthMetres: lengthMetres,
            collectedSegmentCount: segments.count,
            segmentCount: segmentCount)
    }

    /// The date on which the completion first met the condition: the
    /// `collectedAt` of the segment whose collection lifted it there. The
    /// segments must all belong to the goal. It is nil if the completion
    /// with all of them does not meet the condition.
    func firstDate(of segments: [CollectedSegment], where condition: (Completion) -> Bool) -> Date? {
        var date: Date?
        forEachCompletion(after: segments) { collectedAt, completion in
            guard condition(completion) else { return true }
            date = collectedAt
            return false
        }
        return date
    }

    /// Calls the body with the completion after each of the segments, in the
    /// order of time, and with the `collectedAt` of the segment, until the
    /// body returns false. The segments must all belong to the goal.
    fileprivate func forEachCompletion(
        after segments: [CollectedSegment], _ body: (Date, Completion) -> Bool
    ) {
        var length = 0.0
        for (index, segment) in segments.sorted(by: { $0.collectedAt < $1.collectedAt }).enumerated() {
            length += segment.lengthMetres
            let completion = Completion(
                collectedLengthMetres: length, lengthMetres: lengthMetres,
                collectedSegmentCount: index + 1, segmentCount: segmentCount)
            guard body(segment.collectedAt, completion) else { return }
        }
    }
}

nonisolated extension Area {
    /// The date on which the collected segments reached each of the steps:
    /// the `collectedAt` of the segment that lifted the completion over the
    /// step. It needs one pass over the segments, because a higher step is
    /// always reached after a lower one. The segments must all belong to the
    /// area. A step that the segments do not reach has no entry.
    func stepDates(of segments: [CollectedSegment], steps: [StampStep] = StampStep.areaSteps) -> [StampStep: Date] {
        var left = steps.sorted()
        var dates: [StampStep: Date] = [:]
        forEachCompletion(after: segments) { collectedAt, completion in
            while let step = left.first, step.isReached(by: completion) {
                dates[step] = collectedAt
                left.removeFirst()
            }
            return !left.isEmpty
        }
        return dates
    }
}

/// A step of the stamp of an area, which grows with the completion. It
/// starts as the entry stamp, gets a quarter, a half and three quarters of
/// its outer ring in ink, and is full when the dog completes the area.
nonisolated enum StampStep: Int, CaseIterable, Comparable, Sendable {
    /// The dog has collected a segment of the area.
    case entry = 0
    case quarter = 25
    case half = 50
    case threeQuarters = 75
    /// The dog has completed the area.
    case completed = 100

    /// The steps that are area steps. The full stamp is the completed
    /// record of the area.
    static let areaSteps: [StampStep] = [.entry, .quarter, .half, .threeQuarters]

    /// The share of the outer ring of the round stamp that is in ink. It is
    /// also the completion of the steps between the entry stamp and the full
    /// stamp. The entry stamp is not round, so it has none.
    var inkedShare: Double {
        switch self {
        case .entry: 0
        case .quarter: 0.25
        case .half: 0.5
        case .threeQuarters: 0.75
        case .completed: 1
        }
    }

    /// Whether a dog with the completion of an area has reached the step.
    func isReached(by completion: Completion) -> Bool {
        switch self {
        case .entry: completion.collectedSegmentCount > 0
        case .completed: completion.share >= CollectionRules.completedShare
        default: completion.share >= inkedShare
        }
    }

    static func < (first: StampStep, second: StampStep) -> Bool {
        first.rawValue < second.rawValue
    }
}

/// One step of the stamp of one area, as the goal of an area step record.
nonisolated struct AreaStepID: Hashable, Sendable {
    /// The BFS number of the area.
    let area: Area.ID
    let step: StampStep
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
            (goal.id, goal.completion(with: collectedByGoal[goal.id] ?? []))
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The date on which this dog reached each area step
    /// (`StampStep.areaSteps`) of each of the areas, by the BFS number: the
    /// `collectedAt` of the segment whose collection first lifted the
    /// completion over the step. An area with no collected segment has no
    /// entry.
    func stepDates(of areas: [Area]) -> [Area.ID: [StampStep: Date]] {
        let collectedByArea = Dictionary(grouping: collected.values, by: \.area)
        var dates: [Area.ID: [StampStep: Date]] = [:]
        for area in areas {
            guard let segments = collectedByArea[area.id] else { continue }
            dates[area.id] = area.stepDates(of: segments)
        }
        return dates
    }

    /// The feature IDs of the collected segments of each area, by BFS
    /// number. An area with no collected segment has no entry.
    var collectedFeaturesByArea: [Area.ID: Set<Int>] {
        collected.values.reduce(into: [:]) { result, segment in
            result[segment.area, default: []].insert(segment.fid)
        }
    }
}

/// A permanent record that a dog has reached a goal on this date: it has
/// completed an area or a street, or it has reached a step of the stamp of
/// an area. The goal is the BFS number of an area, the ID of a street or an
/// `AreaStepID`. A map release that later lowers the completion does not
/// remove it.
nonisolated struct CompletedRecord<Dog: Hashable & Sendable, Goal: Hashable & Sendable>: Hashable, Sendable {
    let dog: Dog
    let goal: Goal
    let date: Date
}

nonisolated extension CollectionEngine {
    /// A new completed record for each dog and area that has no record yet
    /// and that the dog has completed, sorted by date. The existing records
    /// stay, as the engine never removes a record.
    static func completedRecords<Dog>(
        collections: [Dog: DogCollection], areas: [Area], existing: [CompletedRecord<Dog, Area.ID>]
    ) -> [CompletedRecord<Dog, Area.ID>] {
        completedRecords(collections: collections, goals: areas, existing: existing)
    }

    /// A new completed record for each dog and street that has no record yet
    /// and that the dog has completed. The rules are the same as for areas.
    static func completedRecords<Dog>(
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
    static func stepRecords<Dog>(
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
    static func completedGoals<Dog, Goal: CompletionGoal>(
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
    static func reachedSteps<Dog>(
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
    static func completedDate<Dog, Goal>(of goal: Goal, for dog: Dog, in records: [CompletedRecord<Dog, Goal>]) -> Date? {
        records.filter { $0.dog == dog && $0.goal == goal }.map(\.date).min()
    }

    private struct DogGoal<Dog: Hashable, Goal: Hashable>: Hashable {
        let dog: Dog
        let goal: Goal
    }
}
