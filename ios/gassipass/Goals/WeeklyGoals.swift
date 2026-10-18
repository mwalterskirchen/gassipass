//
//  WeeklyGoals.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation

/// An ended walk of one dog, as the weekly goals see it.
nonisolated struct GoalWalk: Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceMetres: Double
    /// The segments that this walk alone marked, with the time of each mark
    /// (`WalkMatch.Entry.markedAt`).
    let marks: [Segment.ID: Date]
}

/// The stamps of one dog that can finish a weekly goal: the completed
/// streets, the steps of the area stamps with the full stamps of completed
/// areas (`StampStep.completed`), and the ring stamps.
nonisolated struct GoalRecords: Sendable {
    var streets: [CompletedRecord<UUID, Street.ID>] = []
    var steps: [CompletedRecord<UUID, AreaStepID>] = []
    var rings: [CompletedRecord<UUID, Ring>] = []
}

/// A length that a dog added in a week, at the time when it added it.
nonisolated struct GoalAmount: Equatable, Sendable {
    let date: Date
    let metres: Double
}

/// What one dog did in one week that counts for the weekly goals, from its
/// walks and its collection (ADR 0007: the progress is not stored).
nonisolated struct GoalEvents: Sendable {
    let week: DateInterval
    /// The segments that became collected in the week.
    var newSegments: [GoalAmount]
    /// The collected segments whose marks a walk of the week refreshed when
    /// they were older than two weeks, each segment once.
    var refreshed: [GoalAmount]
    /// The counted distance of each walk that started in the week
    /// (`DogDistance`), at the end of the walk.
    var walked: [GoalAmount]
    /// The stamps with a date in the week.
    var records: GoalRecords

    /// - Parameters:
    ///   - walks: The ended walks of the dog. A refresh needs the walks of
    ///     the two weeks before the week too.
    ///   - records: The stamps of the dog.
    init(week: DateInterval, collection: DogCollection, walks: [GoalWalk], records: GoalRecords) {
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

/// The progress of a dog on one weekly goal.
nonisolated struct GoalProgress: Equatable, Sendable {
    /// The length so far, or nil for a goal that a stamp finishes.
    let amountMetres: Double?
    /// The time at which the dog finished the goal, or nil.
    let finishedAt: Date?
}

/// The rules of the weekly goals: their progress, the goals that a dog
/// gets, the swap, the week stamp and the streak. It has no user interface,
/// storage or networking.
nonisolated enum WeeklyGoals {
    /// A refresh goal counts a mark that is at least this old, two weeks.
    static let oldMarkSeconds: TimeInterval = 14 * 86_400

    /// The progress of the dog on the goal with what it did in the week.
    static func progress(of goal: WeeklyGoal, in events: GoalEvents) -> GoalProgress {
        let records = events.records
        switch goal {
        case .newLength(let metres):
            return progress(of: events.newSegments, target: metres)
        case .refresh(let metres):
            return progress(of: events.refreshed, target: metres)
        case .distance(let metres):
            return progress(of: events.walked, target: metres)
        case .street(let street):
            return stamped(records.streets.filter { street == nil || $0.goal == street })
        case .newArea:
            return stamped(records.steps.filter { $0.goal.step == .entry })
        case .areaStep(let step):
            return stamped(records.steps.filter { $0.goal.area == step.area && $0.goal.step >= step.step })
        case .ring(let number):
            return stamped(records.rings.filter { $0.goal.number >= number })
        }
    }

    /// The sum of the amounts, and the time of the amount that lifted the
    /// sum to the target.
    private static func progress(of amounts: [GoalAmount], target: Double) -> GoalProgress {
        var sum = 0.0
        var finishedAt: Date?
        for amount in amounts.sorted(by: { $0.date < $1.date }) {
            sum += amount.metres
            if finishedAt == nil, sum >= target - lengthTolerance {
                finishedAt = amount.date
            }
        }
        return GoalProgress(amountMetres: sum, finishedAt: finishedAt)
    }

    /// The date of the earliest of the stamps.
    private static func stamped<Goal>(_ records: [CompletedRecord<UUID, Goal>]) -> GoalProgress {
        GoalProgress(amountMetres: nil, finishedAt: records.map(\.date).min())
    }

    /// A sum of lengths that is this close to the target reaches it.
    private static let lengthTolerance = 0.5
}

/// What a dog did in an average week of the four weeks before a week.
nonisolated struct AverageWeek: Equatable, Sendable {
    var newMetres: Double
    var walkedMetres: Double
    var refreshedMetres: Double

    /// The average week of a dog that has walked before, but not in the
    /// four weeks before the week. Its goals get the smallest sizes.
    static let quiet = AverageWeek(newMetres: 0, walkedMetres: 0, refreshedMetres: 0)
}

/// A goal near the home base that a stamp finishes: a street that the dog
/// has not completed, the next step of the area of the home base, or the
/// current ring, with the length that the dog still has to collect for it.
nonisolated struct NearGoal: Equatable, Sendable {
    let goal: WeeklyGoal
    let missingMetres: Double
}

/// The sizes of the weekly goals, as shares of an average week. We tune
/// them with the replay tool (`GoalReplay`).
nonisolated enum GoalSizes {
    /// The easy goal asks for about half an average week, of a kind that
    /// fits the usual round.
    static let easyShare = 0.5
    /// The middle goal asks for about one average week of new segments.
    static let middleShare = 1.0
    /// The hard goal asks for a longer walk, or for more new segments.
    static let hardDistanceShare = 1.5
    static let hardNewShare = 2.0
    /// A street or a step close to the home base is a middle goal when the
    /// dog has to collect at most this share of an average week for it.
    static let nearShare = 1.5
    /// An easy goal of refreshed marks needs an average week with at least
    /// this length of refreshed marks.
    static let refreshMinimumMetres = 400.0

    static let easyDistanceMinimumMetres = 1_000.0
    static let hardDistanceMinimumMetres = 3_000.0
    static let refreshMinimumTargetMetres = 300.0
    static let middleNewMinimumMetres = 200.0
    static let hardNewMinimumMetres = 500.0
    /// A near goal fits a dog that collects little, as if the average week
    /// had this much new length.
    static let nearMinimumMetres = 300.0
    /// The number of near streets that can be a middle goal.
    static let nearStreetCount = 3

    /// A distance rounded to half kilometres, and a length of segments to
    /// 100 m, so that the goals read well.
    static func distance(_ metres: Double, minimum: Double) -> Double {
        max(minimum, (metres / 500).rounded() * 500)
    }

    static func length(_ metres: Double, minimum: Double) -> Double {
        max(minimum, (metres / 100).rounded() * 100)
    }
}

nonisolated extension WeeklyGoals {
    /// The goals of a dog in its first week: walk 1 km, complete any street,
    /// and complete ring 1.
    static let starterGoals: [WeeklyGoal] = [.distance(metres: 1_000), .street(nil), .ring(1)]

    /// The goals that a starter goal can be swapped for, by slot.
    private static let starterSwaps: [[WeeklyGoal]] = [
        [.distance(metres: 1_000)], [.newLength(metres: 500)], [.newArea],
    ]

    /// The three goals of the dog for the week: the starter goals for a dog
    /// without a walk before the week, or else goals sized from the average
    /// week. The same dog, week and walks always give the same goals.
    ///
    /// - Parameters:
    ///   - walks: The ended walks of the dog, at least those of the six
    ///     weeks before the week.
    ///   - nearGoals: The goals near the home base, the nearest first.
    static func goals(
        for dog: UUID, week: DateInterval, collection: DogCollection, walks: [GoalWalk], nearGoals: [NearGoal]
    ) -> [WeeklyGoal] {
        guard hasWalked(before: week, walks) else { return starterGoals }
        return candidates(week: week, collection: collection, walks: walks, nearGoals: nearGoals)
            .enumerated()
            .map { slot, options in choose(from: options, dog: dog, week: week, salt: slot) }
    }

    /// The set with another goal of the same size in the slot, or nil when
    /// the set has had its swap, the goal of the slot is finished, or no
    /// other goal fits.
    static func swap(
        slot: Int, of set: WeeklyGoalSet, collection: DogCollection, walks: [GoalWalk], nearGoals: [NearGoal]
    ) -> WeeklyGoalSet? {
        guard set.swappedSlot == nil, set.slots.indices.contains(slot), set.slots[slot].finishedAt == nil
        else { return nil }
        let week = set.week
        let options = hasWalked(before: week, walks)
            ? candidates(week: week, collection: collection, walks: walks, nearGoals: nearGoals)[slot]
            : starterSwaps[slot]
        let goals = set.slots.map(\.goal)
        let others = options.filter { !goals.contains($0) }
        guard !others.isEmpty else { return nil }
        var swapped = set
        swapped.slots[slot] = GoalSlot(
            goal: choose(from: others, dog: set.dog, week: week, salt: WeeklyGoalSet.slotCount + slot), finishedAt: nil)
        swapped.swappedSlot = slot
        return swapped
    }

    /// The average week of the four weeks before the week, from the weeks
    /// in which the dog walked, or nil when it did not walk in them. A week
    /// without a walk, for example a holiday, does not make it smaller.
    static func averageWeek(before week: DateInterval, collection: DogCollection, walks: [GoalWalk]) -> AverageWeek? {
        let weeks = (1...4).map { WeekCalendar.week(startingAt: WeekCalendar.weekStart(week.start, movedBy: -$0)) }
            .filter { week in walks.contains { week.holds($0.startedAt) } }
        guard !weeks.isEmpty else { return nil }
        var sum = AverageWeek.quiet
        for week in weeks {
            let events = GoalEvents(week: week, collection: collection, walks: walks, records: GoalRecords())
            sum.newMetres += events.newSegments.reduce(0) { $0 + $1.metres }
            sum.walkedMetres += events.walked.reduce(0) { $0 + $1.metres }
            sum.refreshedMetres += events.refreshed.reduce(0) { $0 + $1.metres }
        }
        let count = Double(weeks.count)
        return AverageWeek(
            newMetres: sum.newMetres / count, walkedMetres: sum.walkedMetres / count,
            refreshedMetres: sum.refreshedMetres / count)
    }

    private static func hasWalked(before week: DateInterval, _ walks: [GoalWalk]) -> Bool {
        walks.contains { $0.startedAt < week.start }
    }

    /// The goals that fit each slot: the easy, the middle and the hard one.
    private static func candidates(
        week: DateInterval, collection: DogCollection, walks: [GoalWalk], nearGoals: [NearGoal]
    ) -> [[WeeklyGoal]] {
        let average = averageWeek(before: week, collection: collection, walks: walks) ?? .quiet
        var easy: [WeeklyGoal] = [.distance(metres: GoalSizes.distance(
            average.walkedMetres * GoalSizes.easyShare, minimum: GoalSizes.easyDistanceMinimumMetres))]
        if average.refreshedMetres >= GoalSizes.refreshMinimumMetres {
            easy.append(.refresh(metres: GoalSizes.length(
                average.refreshedMetres * GoalSizes.easyShare, minimum: GoalSizes.refreshMinimumTargetMetres)))
        }
        let nearLimit = max(average.newMetres, GoalSizes.nearMinimumMetres) * GoalSizes.nearShare
        let near = nearGoals.filter { $0.missingMetres <= nearLimit }
        let nearStreets = near.filter { if case .street = $0.goal { true } else { false } }
            .prefix(GoalSizes.nearStreetCount)
        let nearSteps = near.filter { if case .street = $0.goal { false } else { true } }
        let middle: [WeeklyGoal] = [.newLength(metres: GoalSizes.length(
            average.newMetres * GoalSizes.middleShare, minimum: GoalSizes.middleNewMinimumMetres))]
            + nearStreets.map(\.goal) + nearSteps.map(\.goal)
        let hard: [WeeklyGoal] = [
            .distance(metres: GoalSizes.distance(
                average.walkedMetres * GoalSizes.hardDistanceShare, minimum: GoalSizes.hardDistanceMinimumMetres)),
            .newLength(metres: GoalSizes.length(
                average.newMetres * GoalSizes.hardNewShare, minimum: GoalSizes.hardNewMinimumMetres)),
            .newArea,
        ]
        return [easy, middle, hard]
    }

    /// One of the goals, the same one for the same dog, week and salt on
    /// every phone. The choice gives each of the goals about the same
    /// chance.
    private static func choose(from goals: [WeeklyGoal], dog: UUID, week: DateInterval, salt: Int) -> WeeklyGoal {
        // FNV-1a, because the hash of Swift changes with each launch.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(dog.uuidString)|\(WeekCalendar.dayText(of: week.start))|\(salt)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return goals[Int(hash % UInt64(goals.count))]
    }
}

/// How the year page of the collection book marks a week.
nonisolated enum WeekMark: Equatable, Sendable {
    /// The dog finished all three goals.
    case weekStamp
    /// The dog finished one or two goals.
    case finishedGoals
    /// The dog had no walk in the week, which pauses the streak.
    case paused
    /// Nothing: a week before the first walk, a week that has not begun, or
    /// a week with walks and no finished goal.
    case none
}

/// One week of the year page.
nonisolated struct YearWeek: Equatable, Sendable, Identifiable {
    let weekStart: Date
    let mark: WeekMark

    var id: Date { weekStart }
}

nonisolated extension WeeklyGoals {
    /// The streak of the dog: the number of weeks in a row with at least one
    /// finished goal. It counts back from the last week that has ended. A
    /// week in which the dog had no ended walk is skipped, and a week with
    /// walks and no finished goal ends the count. The current week counts as
    /// soon as it has a finished goal, and it never ends the streak.
    static func streak(of sets: [WeeklyGoalSet], walks: [GoalWalk], now: Date) -> Int {
        let finished = finishedCounts(of: sets)
        let walked = walkedWeeks(walks)
        guard let earliest = (Array(finished.keys) + Array(walked)).min() else { return 0 }
        let current = WeekCalendar.week(containing: now).start
        var streak = (finished[current] ?? 0) > 0 ? 1 : 0
        var week = WeekCalendar.weekStart(current, movedBy: -1)
        while week >= earliest {
            if (finished[week] ?? 0) > 0 {
                streak += 1
            } else if walked.contains(week) {
                break
            }
            week = WeekCalendar.weekStart(week, movedBy: -1)
        }
        return streak
    }

    /// The weeks of the year (by the week numbers of `WeekCalendar`) with
    /// their marks, from week 1.
    static func weeks(ofYear year: Int, sets: [WeeklyGoalSet], walks: [GoalWalk], now: Date) -> [YearWeek] {
        let calendar = WeekCalendar.calendar
        let finished = finishedCounts(of: sets)
        let walked = walkedWeeks(walks)
        let firstWalkedWeek = walked.min()
        guard var week = calendar.date(from: DateComponents(weekday: 2, weekOfYear: 1, yearForWeekOfYear: year))
        else { return [] }
        var weeks: [YearWeek] = []
        while calendar.component(.yearForWeekOfYear, from: week) == year {
            let end = WeekCalendar.weekStart(week, movedBy: 1)
            let mark: WeekMark
            if week > now {
                mark = .none
            } else if (finished[week] ?? 0) == WeeklyGoalSet.slotCount {
                mark = .weekStamp
            } else if (finished[week] ?? 0) > 0 {
                mark = .finishedGoals
            } else if end <= now, !walked.contains(week), let firstWalkedWeek, week > firstWalkedWeek {
                mark = .paused
            } else {
                mark = .none
            }
            weeks.append(YearWeek(weekStart: week, mark: mark))
            week = end
        }
        return weeks
    }

    /// The number of finished goals of each week, by the start of the week.
    private static func finishedCounts(of sets: [WeeklyGoalSet]) -> [Date: Int] {
        Dictionary(sets.map { ($0.weekStart, $0.finishedCount) }, uniquingKeysWith: max)
    }

    /// The starts of the weeks in which the dog had an ended walk.
    private static func walkedWeeks(_ walks: [GoalWalk]) -> Set<Date> {
        Set(walks.map { WeekCalendar.week(containing: $0.startedAt).start })
    }
}

nonisolated extension DateInterval {
    /// Whether the date lies in the interval, which includes its start and
    /// not its end, so that a date lies in one week only.
    func holds(_ date: Date) -> Bool {
        start <= date && date < end
    }
}
