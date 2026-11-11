//
//  Collections+Passport.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation

extension Collections {
    /// The pages of every area of the canton for the dog, for the passport.
    /// The passport shows many areas, so the pages are built only when the
    /// areas, the collections or the records of the dog change.
    public func pages(canton: String, for dog: Dog) -> [Passport.Page] {
        // These reads come first, so that the screen observes the areas and
        // the collection also when the cache holds the pages. The screen sees
        // new records through its fetch request of the dogs.
        let areas = areas
        let collection = collection(of: dog.id)
        let records = dog.completedAreaRecords
        let steps = stepRecords(of: dog.id)
        let key = PageKey(canton: canton, dog: dog.id, records: records, steps: steps)
        if let pages = pageCache[key] { return pages }
        let pages = Passport.pages(
            canton: canton, areas: Array(areas.values), collection: collection,
            dog: dog.id, records: records, steps: steps)
        pageCache[key] = pages
        return pages
    }

    /// The canton where the dog has collected the most segments, or nil if
    /// the dog has collected none.
    public func cantonWithMostCollected(by dog: UUID?) -> String? {
        let areas = areas
        let collection = collection(of: dog)
        if let canton = cantonCache[dog] { return canton }
        var countByCanton: [String: Int] = [:]
        for segment in collection.collected.values {
            if let canton = areas[segment.area]?.canton {
                countByCanton[canton, default: 0] += 1
            }
        }
        let canton = countByCanton.isEmpty
            ? nil : cantons.max { (countByCanton[$0] ?? 0) < (countByCanton[$1] ?? 0) }
        cantonCache[dog] = canton
        return canton
    }

    /// The totals of the dog, for the home screen, or nil until an update
    /// has built the collection of the dog, because the update adds the
    /// records of newly completed goals.
    public func totals(of dog: Dog) -> DogTotals? {
        guard byDog[dog.id] != nil else { return nil }
        return DogTotals(
            dog: dog.id,
            areaRecords: dog.completedAreaRecords, streetRecords: dog.completedStreetRecords)
    }

    /// The number of segments that the dog collected during the walk, for
    /// the home screen, or nil until an update has built the collection of
    /// the dog with the walk. A walk that has just ended, or a walk that a
    /// dog has just joined, has no count until the next update ends.
    public func collectedSegmentCount(during walk: Walk, of dog: Dog) -> Int? {
        guard let endedAt = walk.endedAt, isBuilt(walk, for: dog.id) else { return nil }
        return collection(of: dog.id).collectedSegmentCount(during: walk.startedAt...endedAt)
    }

    /// Whether the last update built the walk into the collection of the dog.
    public func isBuilt(_ walk: Walk, for dog: UUID) -> Bool {
        byDog[dog] != nil && walksByDog[dog]?.contains(walk.id) == true
    }

    /// The feature IDs of the segments that the walk collected for at least
    /// one of its dogs, for the map of the walk. It is empty until an update
    /// has built the collections with the walk.
    public func collectedFeatures(during walk: Walk) -> Set<Int> {
        guard let endedAt = walk.endedAt else { return [] }
        var features: Set<Int> = []
        for dog in walk.dogs where isBuilt(walk, for: dog.id) {
            features.formUnion(collection(of: dog.id).collectedFeatures(during: walk.startedAt...endedAt))
        }
        return features
    }

    /// The pages of the pinned areas for the dog, for the home screen.
    public func pinnedPages(_ pinned: [Area.ID], for dog: Dog) -> [Passport.Page] {
        Passport.pinnedPages(
            pinned: pinned, areas: Array(areas.values), collection: collection(of: dog.id),
            dog: dog.id, records: dog.completedAreaRecords, steps: stepRecords(of: dog.id))
    }
}

struct PageKey: Hashable {
    let canton: String
    let dog: UUID
    let records: [CompletedRecord<UUID, Area.ID>]
    let steps: [CompletedRecord<UUID, AreaStepID>]
}
