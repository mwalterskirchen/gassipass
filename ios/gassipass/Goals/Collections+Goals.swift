//
//  Collections+Goals.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import OSLog
import SwiftData

/// The weekly goals of the dogs, for the screens: the sets of the store, the
/// progress from the walks, the finishes that the updates store, the swap,
/// and the notifications.
extension Collections {
    /// The weekly goals need the marks of the walks of this many weeks
    /// before the current week: four weeks for the average week, and two
    /// weeks before them for the marks that a refresh counts.
    static let goalWeeks = 6

    private static let goalLogger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "WeeklyGoals")

    /// The start of the first week whose walks the weekly goals need.
    static func goalWindowStart(at now: Date) -> Date {
        WeekCalendar.weekStart(WeekCalendar.week(containing: now).start, movedBy: -goalWeeks)
    }

    /// The sets of the store that are not deleted and that this build can
    /// read.
    static func storedGoalSets(in context: ModelContext) throws -> [WeeklyGoalSet] {
        try context.fetch(shownGoalSets).compactMap(\.goalSet)
    }

    private static let shownGoalSets = FetchDescriptor<StoredGoalSet>(predicate: #Predicate { $0.deletedAt == nil })

    /// The ended walks of the dog, with the marks of the recent ones.
    func goalWalks(of dog: UUID, in walks: [Walk]) -> [GoalWalk] {
        walks.compactMap { walk in
            guard let key = WalkMatchCache.Key(walk), walk.dogs.contains(where: { $0.id == dog }) else { return nil }
            return GoalWalk(
                id: walk.id, startedAt: key.startedAt, endedAt: key.endedAt, distanceMetres: key.distanceMetres,
                marks: walkMarks[key] ?? [:])
        }
    }

    /// The stamps of the dog that can finish a weekly goal.
    func goalRecords(of dog: Dog) -> GoalRecords {
        GoalRecords(
            streets: dog.completedStreetRecords,
            steps: stepRecords(of: dog.id) + dog.completedAreaRecords.map {
                CompletedRecord(dog: dog.id, goal: AreaStepID(area: $0.goal, step: .completed), date: $0.date)
            },
            rings: ringRecords(of: dog.id))
    }

    /// The set of the dog for the week that contains the date, if any.
    func goalSet(of dog: UUID, at date: Date) -> WeeklyGoalSet? {
        let start = WeekCalendar.week(containing: date).start
        return goalSets.first { $0.dog == dog && $0.weekStart.isSameMillisecond(as: start) }
    }

    /// Makes the sets of the current week for the dogs of the pack that have
    /// none, after the update that runs now, or with the next update when
    /// none has ended yet: the first phone of the pack that opens the app in
    /// a new week makes them (ADR 0007). A retired dog gets no set. The app
    /// calls it after the download of the pack, so that a phone takes the
    /// sets of another phone when there are some.
    func makeWeeklyGoals() async {
        areGoalSetsDue = true
        await waitForUpdate()
        // An update that was cancelled leaves the sets to the next one.
        guard hasUpdated else { return }
        makeDueGoalSets()
    }

    /// Makes the sets that the app asked for, if it asked.
    func makeDueGoalSets() {
        guard areGoalSetsDue else { return }
        areGoalSetsDue = false
        do {
            let week = WeekCalendar.week(containing: now())
            let walks = try context.fetch(Walk.ended())
            let rows = try context.fetch(FetchDescriptor<StoredGoalSet>())
            var made = false
            for dog in try context.fetch(Dog.canJoinWalks()) where dog.pack != nil {
                guard !rows.contains(where: { $0.isSet(of: dog.id, weekStart: week.start) }) else { continue }
                let goals = WeeklyGoals.goals(
                    for: dog.id, week: week, collection: collection(of: dog.id), walks: goalWalks(of: dog.id, in: walks),
                    nearGoals: nearGoals(of: dog), farStreets: farStreets(of: dog))
                _ = StoredGoalSet(
                    WeeklyGoalSet(
                        dog: dog.id, weekStart: week.start, slots: goals.map { GoalSlot(goal: $0, finishedAt: nil) },
                        swappedSlot: nil),
                    context: context)
                made = true
            }
            if made {
                try context.save()
            }
            try updateGoals(dogs: try context.fetch(Dog.all()), walks: walks)
        } catch {
            Self.goalLogger.error("The weekly goals cannot be made: \(String(describing: error), privacy: .public)")
        }
    }

    /// Swaps the goal in the slot of the current set of the dog for another
    /// goal of the same size. It returns false when the set has had its
    /// swap, the goal is finished, or no other goal fits.
    @discardableResult
    func swapGoal(inSlot slot: Int, of dog: Dog) -> Bool {
        do {
            let start = WeekCalendar.week(containing: now()).start
            let walks = try context.fetch(Walk.ended())
            guard let row = try context.fetch(Self.shownGoalSets).first(where: { $0.isSet(of: dog.id, weekStart: start) }),
                  let set = row.goalSet,
                  let swapped = WeeklyGoals.swap(
                      slot: slot, of: set, collection: collection(of: dog.id), walks: goalWalks(of: dog.id, in: walks),
                      nearGoals: nearGoals(of: dog), farStreets: farStreets(of: dog))
            else { return false }
            row.update(to: swapped)
            row.noteChange(at: now())
            try context.save()
            // The walks of the week can have finished the new goal already.
            try updateGoals(dogs: try context.fetch(Dog.all()), walks: walks)
            return true
        } catch {
            Self.goalLogger.error("The goal cannot be swapped: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Stores the time at which each dog finished each goal of its sets of
    /// the current week and the week before, from the walks, and keeps the
    /// earliest time. The week before counts too, because a walk of Sunday
    /// can arrive from another phone on Monday. A finish stays when its walk
    /// is deleted. Then it schedules the notifications.
    func updateGoals(dogs: [Dog], walks: [Walk]) throws {
        let now = now()
        let previous = WeekCalendar.weekStart(WeekCalendar.week(containing: now).start, movedBy: -1)
        let dogByID = Dictionary(dogs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for row in try context.fetch(Self.shownGoalSets) where row.weekStart >= previous {
            guard let set = row.goalSet, let dog = dogByID[set.dog] else { continue }
            let events = GoalEvents(
                week: set.week, collection: collection(of: dog.id), walks: goalWalks(of: dog.id, in: walks),
                records: goalRecords(of: dog))
            var updated = set
            for (index, slot) in set.slots.enumerated() {
                guard let finishedAt = WeeklyGoals.progress(of: slot.goal, in: events).finishedAt else { continue }
                // The server keeps milliseconds only.
                if slot.finishedAt.map({ finishedAt < $0 - 0.001 }) ?? true {
                    updated.slots[index].finishedAt = finishedAt
                }
            }
            guard updated != set else { continue }
            row.update(to: updated)
            row.noteChange(at: now)
            changed = true
        }
        if changed {
            try context.save()
        }
        goalSets = try Self.storedGoalSets(in: context)
        scheduleReminders()
    }

    /// Schedules the notifications of the weekly goals again, for example
    /// after a switch in the settings.
    func scheduleReminders() {
        guard let reminders else { return }
        do {
            let dogs = try context.fetch(Dog.canJoinWalks()).filter { $0.pack != nil }
            reminders.schedule(
                for: dogs.map { (id: $0.id, name: $0.name) }, sets: goalSets, at: now(),
                title: { [weak self] in self?.title(of: $0) ?? "" })
        } catch {
            Self.goalLogger.error("The notifications cannot be scheduled: \(String(describing: error), privacy: .public)")
        }
    }

    /// The goals near the home base for the dog: the streets of the segments
    /// around it that the dog has not completed, the nearest first, the next
    /// step of the area of the home base, and the current ring, each with
    /// the length that the dog still has to collect.
    func nearGoals(of dog: Dog) -> [NearGoal] {
        guard let ringSegments, let homeBase, ringSegments.centre == homeBase else { return [] }
        let collection = collection(of: dog.id)
        var goals: [NearGoal] = []
        let completedStreets = Set(dog.completedStreetRecords.map(\.goal))
        var seen: Set<Street.ID> = []
        for segment in ringSegments.segments {
            guard let id = segment.street, !completedStreets.contains(id), seen.insert(id).inserted,
                  let street = streets[id.area]?.first(where: { $0.id == id })
            else { continue }
            let completion = collection.completions(of: [street])[id]
            let missing = street.lengthMetres - (completion?.collectedLengthMetres ?? 0)
            if missing > 0, completion?.collectedSegmentCount != street.segmentCount {
                goals.append(NearGoal(goal: .street(id), missingMetres: missing))
            }
        }
        if let areaID = ringSegments.segments.first?.area, let area = areas[areaID] {
            let completion = collection.completion(of: area)
            let reached = Set(stepRecords(of: dog.id).filter { $0.goal.area == areaID }.map(\.goal.step))
                .union(dog.completedAreaRecords.contains { $0.goal == areaID } ? [.completed] : [])
            let next = StampStep.allCases.first { $0 != .entry && !reached.contains($0) && !$0.isReached(by: completion) }
            if let next {
                let share = next == .completed ? CollectionRules.completedShare : next.inkedShare
                goals.append(NearGoal(
                    goal: .areaStep(AreaStepID(area: areaID, step: next)),
                    missingMetres: share * completion.lengthMetres - completion.collectedLengthMetres))
            }
        }
        if let status = ringStatus(of: dog.id, at: now()) {
            goals.append(NearGoal(
                goal: .ring(status.ring.number),
                missingMetres: CollectionRules.completedShare * status.completion.lengthMetres
                    - status.completion.collectedLengthMetres))
        }
        return goals
    }

    /// The streets far from the usual rounds for the dog: the streets of
    /// the areas that it has entered, with no segment near the home base,
    /// that it has not completed, the shortest missing length first.
    func farStreets(of dog: Dog) -> [NearGoal] {
        let collection = collection(of: dog.id)
        let near = Set(ringSegments?.segments.compactMap(\.street) ?? [])
        let completed = Set(dog.completedStreetRecords.map(\.goal))
        let entered = Set(collection.collected.values.map(\.area))
        let candidates = entered.flatMap { streets[$0] ?? [] }
            .filter { !near.contains($0.id) && !completed.contains($0.id) }
        let completions = collection.completions(of: candidates)
        return candidates
            .compactMap { street -> NearGoal? in
                let completion = completions[street.id]
                guard completion?.collectedSegmentCount != street.segmentCount else { return nil }
                return NearGoal(
                    goal: .street(street.id),
                    missingMetres: street.lengthMetres - (completion?.collectedLengthMetres ?? 0))
            }
            .sorted { $0.missingMetres < $1.missingMetres }
    }

    /// The weekly goals of the dog for the week that contains the date, with
    /// the progress on each goal, or nil when the dog has no set for it.
    func goalStatus(of dog: Dog, walks: [Walk], at date: Date) -> GoalStatus? {
        guard let set = goalSet(of: dog.id, at: date) else { return nil }
        let collection = collection(of: dog.id)
        let goalWalks = goalWalks(of: dog.id, in: walks)
        let events = GoalEvents(
            week: set.week, collection: collection, walks: goalWalks, records: goalRecords(of: dog))
        let lines = set.slots.enumerated().map { index, slot in
            let progress = WeeklyGoals.progress(of: slot.goal, in: events)
            let finishedAt = [slot.finishedAt, progress.finishedAt].compactMap { $0 }.min()
            return GoalLine(
                slot: index, goal: slot.goal, title: title(of: slot.goal), finishedAt: finishedAt,
                amountMetres: progress.amountMetres,
                share: finishedAt != nil ? 1 : share(of: slot.goal, progress: progress, for: dog.id, in: collection))
        }
        return GoalStatus(
            goalSet: set, lines: lines,
            streak: WeeklyGoals.streak(of: goalSets.filter { $0.dog == dog.id }, walks: goalWalks, now: date))
    }

    /// The progress on each weekly goal of the dogs of the ended walk, after
    /// the walk, for its summary: the goals of the week in which the walk
    /// started. It is nil until the summary of the walk is ready
    /// (`summary(of:)`). A dog without a set for that week has no lines.
    func goalProgress(of walk: Walk, walks: [Walk]) -> [WalkGoalProgress]? {
        guard let endedAt = walk.endedAt, summary(of: walk) != nil else { return nil }
        let time = walk.startedAt...endedAt
        let dogs = walk.dogs
            .filter { $0.deletedAt == nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return dogs.flatMap { dog in
            let status = goalStatus(of: dog, walks: walks.filter { $0.hasDog(dog) }, at: walk.startedAt)
            return (status?.lines ?? []).map { line in
                WalkGoalProgress(
                    dog: dog.id, dogName: dog.name, line: line,
                    isFinishedOnWalk: line.finishedAt.map(time.contains) ?? false)
            }
        }
    }

    /// The replay of the last 12 weeks of the dog through the rules of the
    /// weekly goals, as text (`GoalReplay`).
    func goalReplay(of dog: Dog) async throws -> String {
        let walks = try context.fetch(Walk.ended()).filter { $0.hasDog(dog) }
        let marks = try await storedMarks(of: walks)
        let goalWalks = walks.compactMap { walk -> GoalWalk? in
            guard let key = WalkMatchCache.Key(walk) else { return nil }
            return GoalWalk(
                id: walk.id, startedAt: key.startedAt, endedAt: key.endedAt, distanceMetres: key.distanceMetres,
                marks: marks[key] ?? [:])
        }
        let weeks = GoalReplay.weeks(
            of: dog.id, collection: collection(of: dog.id), walks: goalWalks, records: goalRecords(of: dog),
            nearGoals: nearGoals(of: dog), farStreets: farStreets(of: dog), now: now())
        return GoalReplay.report(weeks, title: title(of:))
    }

    /// The sets of the dog, for the year pages of the collection book.
    func goalSets(of dog: UUID) -> [WeeklyGoalSet] {
        goalSets.filter { $0.dog == dog }
    }

    /// How far the dog has come on a goal that it has not finished, from 0
    /// to 1.
    private func share(of goal: WeeklyGoal, progress: GoalProgress, for dog: UUID, in collection: DogCollection) -> Double {
        if let target = goal.targetMetres {
            return min((progress.amountMetres ?? 0) / target, 1)
        }
        switch goal {
        case .street(let id?):
            guard let street = streets[id.area]?.first(where: { $0.id == id }) else { return 0 }
            return collection.completions(of: [street])[id]?.share ?? 0
        case .areaStep(let step):
            guard let area = areas[step.area] else { return 0 }
            let share = step.step == .completed ? CollectionRules.completedShare : step.step.inkedShare
            return share > 0 ? min(collection.completion(of: area).share / share, 1) : 0
        case .ring(let number):
            guard let ringSegments, let homeBase else { return 0 }
            let ring = Ring(number: number, centre: homeBase)
            guard ringSegments.holds(ring) else { return 0 }
            return min(ringSegments.completion(of: ring, for: collection).share / CollectionRules.completedShare, 1)
        default:
            return 0
        }
    }

    /// The goal in words, for example "Walk 5 km" or "Reach 50% of Dietikon".
    func title(of goal: WeeklyGoal) -> String {
        GoalText.title(of: goal, areaName: { areas[$0]?.name })
    }
}

/// The weekly goals of a dog for a week, with the progress on each goal.
struct GoalStatus: Equatable {
    let goalSet: WeeklyGoalSet
    let lines: [GoalLine]
    /// The streak of the dog.
    let streak: Int

    var finishedCount: Int {
        lines.count { $0.finishedAt != nil }
    }

    var hasWeekStamp: Bool {
        finishedCount == WeeklyGoalSet.slotCount
    }

    /// Whether a member can still swap a goal of the set.
    var canSwap: Bool {
        goalSet.swappedSlot == nil
    }
}

/// One weekly goal with the progress of the dog on it.
struct GoalLine: Equatable, Identifiable {
    let slot: Int
    let goal: WeeklyGoal
    let title: String
    /// The time at which the dog finished the goal, or nil.
    let finishedAt: Date?
    /// The length so far, or nil for a goal that a stamp finishes.
    let amountMetres: Double?
    /// How far the dog has come, from 0 to 1.
    let share: Double

    var id: Int { slot }
}

/// The progress of one dog on one weekly goal after a walk.
struct WalkGoalProgress: Equatable, Identifiable {
    let dog: UUID
    let dogName: String
    let line: GoalLine
    /// Whether the walk finished the goal.
    let isFinishedOnWalk: Bool

    var id: String { "\(dog.uuidString)-\(line.slot)" }
}
