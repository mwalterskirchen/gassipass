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
    /// The stamps that the dogs earned on the walk: the records whose dates
    /// lie within the walk, in the order of their dates. Each area shows
    /// once, with the highest step that the walk reached for its dogs.
    let stamps: [CurrentWalk.CompletedGoal]
}

extension Collections {
    /// The summary of the ended walk, or nil until an update has built the
    /// walk into the collections of all its dogs. The same update stores the
    /// records of the walk, so the summary then lists them.
    func summary(of walk: Walk) -> WalkSummary? {
        guard let endedAt = walk.endedAt else { return nil }
        let time = walk.startedAt...endedAt
        let dogs = walk.dogs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !dogs.isEmpty, dogs.allSatisfy({ isBuilt(walk, for: $0.id) }) else { return nil }

        var newSegments: Set<Segment.ID> = []
        var areaSteps: [Area.ID: [UUID: (step: StampStep, date: Date)]] = [:]
        var streets: [Street.ID: [UUID: Date]] = [:]
        for dog in dogs {
            for (id, segment) in collection(of: dog.id).collected where time.contains(segment.collectedAt) {
                newSegments.insert(id)
            }
            let steps = stepRecords(of: dog.id).map { (area: $0.goal.area, step: $0.goal.step, date: $0.date) }
                + dog.completedAreaRecords.map { (area: $0.goal, step: StampStep.completed, date: $0.date) }
            for record in steps where time.contains(record.date) {
                if let highest = areaSteps[record.area]?[dog.id], highest.step > record.step { continue }
                areaSteps[record.area, default: [:]][dog.id] = (record.step, record.date)
            }
            for record in dog.completedStreetRecords where time.contains(record.date) {
                let earlier = streets[record.goal]?[dog.id] ?? record.date
                streets[record.goal, default: [:]][dog.id] = min(earlier, record.date)
            }
        }

        func names(of dogIDs: some Sequence<UUID>) -> [String] {
            let dogIDs = Set(dogIDs)
            return dogs.filter { dogIDs.contains($0.id) }.map(\.name)
        }
        var stamps: [CurrentWalk.CompletedGoal] = []
        for (area, byDog) in areaSteps {
            let groups = Dictionary(grouping: byDog, by: \.value.step)
            for (step, entries) in groups {
                stamps.append(CurrentWalk.CompletedGoal(
                    id: .area(area, step), name: areas[area]?.name ?? "", area: area,
                    dogNames: names(of: entries.map(\.key)), date: entries.map(\.value.date).min()!))
            }
        }
        for (street, byDog) in streets {
            stamps.append(CurrentWalk.CompletedGoal(
                id: .street(street), name: street.name, area: street.area, dogNames: names(of: byDog.keys),
                date: byDog.values.min()!))
        }
        stamps.sort { ($0.date, $0.name) < ($1.date, $1.name) }
        return WalkSummary(distanceMetres: walk.distanceMetres, newSegmentCount: newSegments.count, stamps: stamps)
    }
}
