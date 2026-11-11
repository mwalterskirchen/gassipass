//
//  GoalEvents.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation

/// An ended walk of one dog, as the weekly goals see it.
public nonisolated struct GoalWalk: Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let distanceMetres: Double
    /// The segments that this walk alone marked, with the time of each mark
    /// (`WalkMatch.Entry.markedAt`).
    public let marks: [Segment.ID: Date]

    public init(id: UUID, startedAt: Date, endedAt: Date, distanceMetres: Double, marks: [Segment.ID: Date]) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMetres = distanceMetres
        self.marks = marks
    }
}

/// The stamps of one dog that can finish a weekly goal: the completed
/// streets, the steps of the area stamps with the full stamps of completed
/// areas (`StampStep.completed`), and the ring stamps.
public nonisolated struct GoalRecords: Sendable {
    public var streets: [CompletedRecord<UUID, Street.ID>] = []
    public var steps: [CompletedRecord<UUID, AreaStepID>] = []
    public var rings: [CompletedRecord<UUID, Ring>] = []

    public init(
        streets: [CompletedRecord<UUID, Street.ID>] = [],
        steps: [CompletedRecord<UUID, AreaStepID>] = [],
        rings: [CompletedRecord<UUID, Ring>] = []
    ) {
        self.streets = streets
        self.steps = steps
        self.rings = rings
    }
}

/// A length that a dog added in a week, at the time when it added it.
public nonisolated struct GoalAmount: Equatable, Sendable {
    public let date: Date
    public let metres: Double

    public init(date: Date, metres: Double) {
        self.date = date
        self.metres = metres
    }
}

/// What one dog did in one week that counts for the weekly goals, from its
/// walks and its collection (ADR 0007: the progress is not stored).
public nonisolated struct GoalEvents: Sendable {
    public let week: DateInterval
    /// The segments that became collected in the week.
    public var newSegments: [GoalAmount]
    /// The collected segments whose marks a walk of the week refreshed when
    /// they were older than two weeks, each segment once.
    public var refreshed: [GoalAmount]
    /// The counted distance of each walk that started in the week
    /// (`DogDistance`), at the end of the walk.
    public var walked: [GoalAmount]
    /// The stamps with a date in the week.
    public var records: GoalRecords

    /// - Parameters:
    ///   - walks: The ended walks of the dog. A refresh needs the walks of
    ///     the two weeks before the week too.
    ///   - records: The stamps of the dog.
    public init(week: DateInterval, collection: DogCollection, walks: [GoalWalk], records: GoalRecords) {
        self.week = week
        newSegments = collection.collected.values
            .filter { week.holds($0.collectedAt) }
            .map { GoalAmount(date: $0.collectedAt, metres: $0.lengthMetres) }
        refreshed = Self.refreshed(in: week, collection: collection, walks: walks)
        walked = DogDistance(walks: walks.map {
            (id: $0.id, startedAt: $0.startedAt, endedAt: $0.endedAt, distanceMetres: $0.distanceMetres)
        })
        .walks
        .filter { week.holds($0.startedAt) && $0.countedMetres > 0 }
        .map { GoalAmount(date: $0.endedAt, metres: $0.countedMetres) }
        self.records = GoalRecords(
            streets: records.streets.filter { week.holds($0.date) },
            steps: records.steps.filter { week.holds($0.date) },
            rings: records.rings.filter { week.holds($0.date) })
    }

    /// The segments that the walks of the week refreshed: segments that the
    /// dog had collected before the walk, and whose mark before the walk was
    /// older than two weeks. A mark is never older than the time when the
    /// segment became collected.
    private static func refreshed(
        in week: DateInterval, collection: DogCollection, walks: [GoalWalk]
    ) -> [GoalAmount] {
        var lastMarks: [Segment.ID: Date] = [:]
        var counted: Set<Segment.ID> = []
        var amounts: [GoalAmount] = []
        for walk in walks.sorted(by: { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }) {
            if week.holds(walk.startedAt) {
                for (id, date) in walk.marks where !counted.contains(id) {
                    guard let segment = collection.collected[id], segment.collectedAt < walk.startedAt else { continue }
                    let previous = max(segment.collectedAt, lastMarks[id] ?? .distantPast)
                    guard date.timeIntervalSince(previous) >= WeeklyGoals.oldMarkSeconds else { continue }
                    counted.insert(id)
                    amounts.append(GoalAmount(date: date, metres: segment.lengthMetres))
                }
            }
            lastMarks.merge(walk.marks, uniquingKeysWith: max)
        }
        return amounts
    }
}
