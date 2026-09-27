//
//  CollectionBook.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation

/// The list of all areas of a canton for one dog, including areas with no
/// completion yet.
nonisolated enum CollectionBook {
    /// One area in the collection book.
    struct Page: Identifiable, Sendable {
        let area: Area
        let completion: Completion
        /// The date on which the dog completed the area, or nil if it has not.
        let completedAt: Date?
        /// The segments of the area that the dog has collected, for the
        /// small map of the area.
        let collectedSegments: Set<Segment.ID>

        var id: Int { area.id }
    }

    /// One street on the screen of its area.
    struct StreetEntry: Identifiable, Sendable {
        let street: Street
        let completion: Completion
        /// The date on which the dog completed the street, or nil if it has not.
        let completedAt: Date?

        var id: Street.ID { street.id }
    }

    /// The pages of every area of the canton, sorted by name.
    static func pages<Dog>(
        canton: String, areas: [Area], collection: DogCollection, dog: Dog, records: [CompletedRecord<Dog, Area.ID>]
    ) -> [Page] {
        let areas = areas
            .filter { $0.canton == canton }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let completions = collection.completions(of: areas)
        let collectedSegments = collection.collectedSegmentsByArea
        return areas.map { area in
            Page(
                area: area,
                completion: completions[area.id]!,
                completedAt: CollectionEngine.completedDate(of: area.id, for: dog, in: records),
                collectedSegments: collectedSegments[area.id] ?? [])
        }
    }

    /// The streets of the area, sorted by name.
    static func streets<Dog>(
        of area: Area.ID, streets: [Street], collection: DogCollection, dog: Dog,
        records: [CompletedRecord<Dog, Street.ID>]
    ) -> [StreetEntry] {
        let streets = streets
            .filter { $0.id.area == area }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let completions = collection.completions(of: streets)
        return streets.map { street in
            StreetEntry(
                street: street,
                completion: completions[street.id]!,
                completedAt: CollectionEngine.completedDate(of: street.id, for: dog, in: records))
        }
    }

    /// The page of one area.
    static func page<Dog>(
        of area: Area, collection: DogCollection, dog: Dog, records: [CompletedRecord<Dog, Area.ID>]
    ) -> Page {
        pages(canton: area.canton, areas: [area], collection: collection, dog: dog, records: records)[0]
    }
}
