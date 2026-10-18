//
//  WalkSummary.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import Foundation

/// What an ended walk earned, for the summary at its end. It comes from the
/// collections and the records after the update that built the walk into
/// them (`Collections.summary(of:)`).
struct WalkSummary: Equatable {
    let distanceMetres: Double
    /// The segments that the walk collected for at least one of its dogs.
    let newSegmentCount: Int
    /// The length of the segments whose marks the walk refreshed for at
    /// least one of its dogs: segments that the dog had collected before
    /// the walk, and that the walk marked.
    let refreshedLengthMetres: Double
    /// The stamps that the dogs earned on the walk: the records whose dates
    /// lie within the walk, in the order of their dates. Each area shows
    /// once, with the highest step that the walk reached, and the dogs that
    /// reached that step.
    let stamps: [CurrentWalk.CompletedGoal]
}

extension Collections {
    /// The summary of the ended walk, or nil until an update has built the
    /// walk into the collections of all its dogs and stored the records of
    /// the walk. A dog that was deleted during the walk does not count. A
    /// walk that has left the store, for example with its pack, has none.
    func summary(of walk: Walk) -> WalkSummary? {
        guard walk.isInStore, let endedAt = walk.endedAt else { return nil }
        let time = walk.startedAt...endedAt
        let dogs = walk.dogs
            .filter { $0.deletedAt == nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !dogs.isEmpty, dogs.allSatisfy({ isBuilt(walk, for: $0.id) }) else { return nil }

        var newSegments: Set<Segment.ID> = []
        var refreshed: [Segment.ID: Double] = [:]
        var areaSteps: [Area.ID: [UUID: (step: StampStep, date: Date)]] = [:]
        var streets: [Street.ID: [UUID: Date]] = [:]
        var rings: [Ring: [UUID: Date]] = [:]
        for dog in dogs {
            for (id, segment) in collection(of: dog.id).collected {
                if time.contains(segment.collectedAt) {
                    newSegments.insert(id)
                } else if time.contains(segment.markedAt) {
                    refreshed[id] = segment.lengthMetres
                }
            }
            let steps = stepRecords(of: dog.id).map { (area: $0.goal.area, step: $0.goal.step, date: $0.date) }
                + dog.completedAreaRecords.map { (area: $0.goal, step: StampStep.completed, date: $0.date) }
            // The highest step of the dog, and of two records of that step
            // the earliest.
            for record in steps where time.contains(record.date) {
                if let highest = areaSteps[record.area]?[dog.id],
                   highest.step > record.step || (highest.step == record.step && highest.date <= record.date) {
                    continue
                }
                areaSteps[record.area, default: [:]][dog.id] = (record.step, record.date)
            }
            for record in dog.completedStreetRecords where time.contains(record.date) {
                let earlier = streets[record.goal]?[dog.id] ?? record.date
                streets[record.goal, default: [:]][dog.id] = min(earlier, record.date)
            }
            for record in ringRecords(of: dog.id) where time.contains(record.date) {
                let earlier = rings[record.goal]?[dog.id] ?? record.date
                rings[record.goal, default: [:]][dog.id] = min(earlier, record.date)
            }
        }

        func names(of dogIDs: some Sequence<UUID>) -> [String] {
            let dogIDs = Set(dogIDs)
            return dogs.filter { dogIDs.contains($0.id) }.map(\.name)
        }
        var stamps: [CurrentWalk.CompletedGoal] = []
        for (area, byDog) in areaSteps {
            guard let step = byDog.values.map(\.step).max() else { continue }
            let reached = byDog.filter { $0.value.step == step }
            stamps.append(CurrentWalk.CompletedGoal(
                id: .area(area, step), name: areas[area]?.name ?? "", area: area,
                dogNames: names(of: reached.keys), date: reached.values.map(\.date).min()!))
        }
        for (street, byDog) in streets {
            stamps.append(CurrentWalk.CompletedGoal(
                id: .street(street), name: street.name, area: street.area, dogNames: names(of: byDog.keys),
                date: byDog.values.min()!))
        }
        for (ring, byDog) in rings {
            stamps.append(CurrentWalk.CompletedGoal(
                id: .ring(ring), name: ring.name, area: nil, dogNames: names(of: byDog.keys),
                date: byDog.values.min()!))
        }
        stamps.sort { ($0.date, $0.name) < ($1.date, $1.name) }
        // A segment that is new for one dog is new, also when the walk
        // refreshes its mark for another.
        let refreshedLength = refreshed.filter { !newSegments.contains($0.key) }.values.reduce(0, +)
        return WalkSummary(
            distanceMetres: walk.distanceMetres, newSegmentCount: newSegments.count,
            refreshedLengthMetres: refreshedLength, stamps: stamps)
    }
}
