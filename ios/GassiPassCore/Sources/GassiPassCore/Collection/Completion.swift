//
//  Completion.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation

/// The collected length of an area, a ring or a street as a share of its total
/// length, for one dog, and the number of collected segments.
public nonisolated struct Completion: Equatable, Sendable {
    public let collectedLengthMetres: Double
    public let lengthMetres: Double
    public let collectedSegmentCount: Int
    public let segmentCount: Int

    /// The completion from 0 to 1. It is exactly 1 when all segments are
    /// collected, because the sum of their lengths can end a little below
    /// the total length.
    public var share: Double {
        if segmentCount > 0, collectedSegmentCount == segmentCount { return 1 }
        return lengthMetres > 0 ? collectedLengthMetres / lengthMetres : 0
    }

    public init(collectedLengthMetres: Double, lengthMetres: Double, collectedSegmentCount: Int, segmentCount: Int) {
        self.collectedLengthMetres = collectedLengthMetres
        self.lengthMetres = lengthMetres
        self.collectedSegmentCount = collectedSegmentCount
        self.segmentCount = segmentCount
    }
}

/// The number and the total length of the segments of an area, a street or
/// a ring, which a completion is a share of.
public nonisolated protocol CompletionTotals: Sendable {
    var segmentCount: Int { get }
    var lengthMetres: Double { get }
}

/// An area or a street: a goal with a completion and completed records.
public nonisolated protocol CompletionGoal: CompletionTotals, Identifiable where ID: Sendable {
    /// The goal of this kind that a collected segment belongs to, if any.
    static func goal(of segment: CollectedSegment) -> ID?
    /// Whether a dog with the completion has completed the goal.
    func isCompleted(_ completion: Completion) -> Bool
}

nonisolated extension Area: CompletionGoal {
    public static func goal(of segment: CollectedSegment) -> Int? { segment.area }

    /// An area is completed at 95% (`CollectionRules.completedShare`).
    public func isCompleted(_ completion: Completion) -> Bool {
        StampStep.completed.isReached(by: completion)
    }
}

nonisolated extension Street: CompletionGoal {
    public static func goal(of segment: CollectedSegment) -> ID? { segment.street }

    /// A street is completed when every segment is collected.
    public func isCompleted(_ completion: Completion) -> Bool {
        completion.segmentCount > 0 && completion.collectedSegmentCount == completion.segmentCount
    }
}

nonisolated extension CompletionTotals {
    /// The completion of the goal with the collected segments, which must
    /// all belong to the goal.
    public func completion(with segments: some Collection<CollectedSegment>) -> Completion {
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
    public func firstDate(of segments: [CollectedSegment], where condition: (Completion) -> Bool) -> Date? {
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
    public func stepDates(of segments: [CollectedSegment], steps: [StampStep] = StampStep.areaSteps) -> [StampStep: Date] {
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
public nonisolated enum StampStep: Int, CaseIterable, Comparable, Sendable {
    /// The dog has collected a segment of the area.
    case entry = 0
    case quarter = 25
    case half = 50
    case threeQuarters = 75
    /// The dog has completed the area.
    case completed = 100

    /// The steps that are area steps. The full stamp is the completed
    /// record of the area.
    public static let areaSteps: [StampStep] = [.entry, .quarter, .half, .threeQuarters]

    /// The share of the outer ring of the round stamp that is in ink. It is
    /// also the completion of the steps between the entry stamp and the full
    /// stamp. The entry stamp is not round, so it has none.
    public var inkedShare: Double {
        switch self {
        case .entry: 0
        case .quarter: 0.25
        case .half: 0.5
        case .threeQuarters: 0.75
        case .completed: 1
        }
    }

    /// Whether a dog with the completion of an area has reached the step.
    public func isReached(by completion: Completion) -> Bool {
        switch self {
        case .entry: completion.collectedSegmentCount > 0
        case .completed: completion.share >= CollectionRules.completedShare
        default: completion.share >= inkedShare
        }
    }

    public static func < (first: StampStep, second: StampStep) -> Bool {
        first.rawValue < second.rawValue
    }
}

/// One step of the stamp of one area, as the goal of an area step record.
public nonisolated struct AreaStepID: Hashable, Sendable {
    /// The BFS number of the area.
    public let area: Area.ID
    public let step: StampStep

    public init(area: Area.ID, step: StampStep) {
        self.area = area
        self.step = step
    }
}

nonisolated extension DogCollection {
    /// The completion of an area for this dog.
    public func completion(of area: Area) -> Completion {
        completions(of: [area])[area.id]!
    }

    /// The completion of each of the areas or streets for this dog, by the
    /// ID of the goal. For an area, the ID is the BFS number.
    public func completions<Goal: CompletionGoal>(of goals: [Goal]) -> [Goal.ID: Completion] {
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
    public func stepDates(of areas: [Area]) -> [Area.ID: [StampStep: Date]] {
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
    public var collectedFeaturesByArea: [Area.ID: Set<Int>] {
        collected.values.reduce(into: [:]) { result, segment in
            result[segment.area, default: []].insert(segment.fid)
        }
    }
}
