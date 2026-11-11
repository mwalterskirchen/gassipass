//
//  Collections+Store.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import OSLog
import SwiftData

/// The collections in the store, which the app shows at launch until the
/// first update ends.
extension Collections {
    /// Shows the collections of the last update until the first update ends.
    /// Collections that cannot be read are rebuilt by the first update.
    func loadStoredCollections() {
        let interval = Self.signposter.beginInterval("Load stored collections")
        defer { Self.signposter.endInterval("Load stored collections", interval) }
        do {
            guard let build = try context.fetch(FetchDescriptor<CollectionBuild>()).first else { return }
            let input = try CollectionInput(data: build.input)
            var byDog = Dictionary(uniqueKeysWithValues: input.dogs.map { ($0, DogCollection()) })
            var entries = Dictionary(uniqueKeysWithValues: input.dogs.map { ($0, [Segment.ID: CoverageHistory.Entry]()) })
            var hasEveryRow = true
            var rowsFollowTheirHistory = true
            for segment in try context.fetch(FetchDescriptor<WalkedSegment>()) {
                if byDog[segment.dogID] == nil {
                    hasEveryRow = false
                }
                byDog[segment.dogID]?.add(segment)
                let entry = segment.historyEntry
                entries[segment.dogID]?[segment.segmentID] = entry
                if entry.parts != CoveredParts(data: segment.coveredParts) || entry.collectedAt != segment.collectedAt {
                    rowsFollowTheirHistory = false
                }
            }
            self.byDog = byDog
            walksByDog = input.walksByDog
            storedBuild = (build.version, input, build.matchedEveryWalk)
            // A store from before the history has no held walks, and its
            // first update builds the history from all walks. So does a store
            // with a row that its history did not write.
            if rowsFollowTheirHistory, let heldWalks = try? CollectionHistory.heldWalks(from: build.heldWalks) {
                let histories = entries.mapValues(CoverageHistory.init(entries:))
                history = (build.version, CollectionHistory(dogs: histories, walks: heldWalks))
                // A row of a dog that the input does not know is not in the
                // collections, so only a store that writes every row deletes it.
                storedHistories = hasEveryRow ? histories : nil
            }
        } catch {
            Self.logger.error("The stored collections cannot be read: \(String(describing: error), privacy: .public)")
        }
    }

    /// Stores the collections and their history for the next launch. It
    /// writes only the rows that changed.
    func storeCollections(
        version: String, input: CollectionInput, history: CollectionHistory, matchedEveryWalk: Bool
    ) throws {
        let interval = Self.signposter.beginInterval("Store collections")
        defer { Self.signposter.endInterval("Store collections", interval) }
        let stored = storedHistories
        // A store that fails can leave rows that the memory does not know.
        storedHistories = nil
        if let stored {
            try storeChangedRows(of: history.dogs, since: stored)
        } else {
            try storeEveryRow(of: history.dogs)
        }
        let data = try input.data()
        let build = try context.fetch(FetchDescriptor<CollectionBuild>()).first ?? {
            let build = CollectionBuild()
            context.insert(build)
            return build
        }()
        build.version = version
        build.input = data
        build.matchedEveryWalk = matchedEveryWalk
        build.heldWalks = try history.heldWalksData()
        try context.save()
        storedBuild = (version, input, matchedEveryWalk)
        storedHistories = history.dogs
    }

    /// Writes the row of each segment whose history changed since the last
    /// store, and deletes the row of each segment that left a history. A new
    /// walk changes some segments, so it fetches only their rows. The kept
    /// intervals of a segment can change without its covered parts, when a
    /// walk is older than the others, so the rows follow the history.
    private func storeChangedRows(
        of histories: [UUID: CoverageHistory], since stored: [UUID: CoverageHistory]
    ) throws {
        var changed: Set<WalkedSegmentKey> = []
        for dog in Set(stored.keys).union(histories.keys) {
            let old = stored[dog]?.entries ?? [:]
            let new = histories[dog]?.entries ?? [:]
            for segment in Set(old.keys).union(new.keys) where old[segment] != new[segment] {
                changed.insert(WalkedSegmentKey(dog: dog, segment: segment))
            }
        }
        guard !changed.isEmpty else { return }
        let dogIDs = Set(changed.map(\.dog))
        let segmentIDs = Set(changed.map(\.segment))
        var rows: [WalkedSegmentKey: WalkedSegment] = [:]
        for row in try context.fetch(FetchDescriptor<WalkedSegment>(predicate: #Predicate {
            dogIDs.contains($0.dogID) && segmentIDs.contains($0.segmentID)
        })) {
            let key = WalkedSegmentKey(dog: row.dogID, segment: row.segmentID)
            guard changed.contains(key) else { continue }
            if rows[key] == nil {
                rows[key] = row
            } else {
                context.delete(row)
            }
        }
        for key in changed {
            if let entry = histories[key.dog]?.entries[key.segment] {
                let row = rows[key] ?? insertedRow(dog: key.dog, segment: key.segment)
                row.update(entry)
            } else if let row = rows[key] {
                context.delete(row)
            }
        }
    }

    /// Writes the row of each segment of the histories, and deletes every
    /// other row, also a second row of the same dog and segment.
    private func storeEveryRow(of histories: [UUID: CoverageHistory]) throws {
        var rows: [WalkedSegmentKey: WalkedSegment] = [:]
        for row in try context.fetch(FetchDescriptor<WalkedSegment>()) {
            let key = WalkedSegmentKey(dog: row.dogID, segment: row.segmentID)
            if rows[key] == nil {
                rows[key] = row
            } else {
                context.delete(row)
            }
        }
        for (dog, history) in histories {
            for (segment, entry) in history.entries {
                let row = rows.removeValue(forKey: WalkedSegmentKey(dog: dog, segment: segment))
                    ?? insertedRow(dog: dog, segment: segment)
                row.update(entry)
            }
        }
        for row in rows.values {
            context.delete(row)
        }
    }

    private func insertedRow(dog: UUID, segment: Segment.ID) -> WalkedSegment {
        let row = WalkedSegment(dogID: dog, segmentID: segment)
        context.insert(row)
        return row
    }
}

/// A row of the stored collections: one dog and one segment.
private struct WalkedSegmentKey: Hashable {
    let dog: UUID
    let segment: Segment.ID
}

extension DogCollection {
    /// Adds the stored segment.
    fileprivate mutating func add(_ segment: WalkedSegment) {
        coveredParts[segment.segmentID] = CoveredParts(data: segment.coveredParts)
        if let collectedAt = segment.collectedAt {
            collected[segment.segmentID] = CollectedSegment(
                fid: segment.fid, area: segment.area,
                street: segment.streetName.map { Street.ID(area: segment.area, name: $0) },
                lengthMetres: segment.lengthMetres, collectedAt: collectedAt,
                markedAt: segment.markedAt ?? collectedAt)
        }
    }
}

extension WalkedSegment {
    /// Gives the row the history of its segment, and the covered parts and
    /// the collected segment that follow from it. It writes only the values
    /// that changed, so that an unchanged row is not saved.
    fileprivate func update(_ entry: CoverageHistory.Entry) {
        set(\.coveredParts, to: entry.parts.data)
        set(\.collectedAt, to: entry.collected?.collectedAt)
        set(\.markedAt, to: entry.collected?.markedAt)
        set(\.fid, to: entry.segment.fid)
        set(\.area, to: entry.segment.area)
        set(\.streetName, to: entry.segment.street?.name)
        set(\.lengthMetres, to: entry.segment.lengthMetres)
        set(\.planeLengthMetres, to: entry.segment.planeLengthMetres)
        set(\.keptIntervals, to: entry.covered.data)
        set(\.walkMarkedAt, to: entry.markedAt)
    }

    /// The history of the segment as the row keeps it.
    fileprivate var historyEntry: CoverageHistory.Entry {
        CoverageHistory.Entry(
            segment: MatchedSegment(
                fid: fid, area: area, street: streetName.map { Street.ID(area: area, name: $0) },
                lengthMetres: lengthMetres, planeLengthMetres: planeLengthMetres),
            covered: [CoveredInterval](data: keptIntervals), markedAt: walkMarkedAt)
    }
}
