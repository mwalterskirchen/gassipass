//
//  Dog.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import SwiftData

/// The owner of a collection. Each dog has its own collection and its own
/// completions.
///
/// The app never deletes a dog. A dog that no longer takes part in walks
/// becomes a retired dog, and its collection, completions and completed
/// records stay.
///
/// The model follows the CloudKit rules of SwiftData, so that sync can start
/// without a migration: every attribute has a default value, every
/// relationship is optional and has an inverse, and nothing is unique.
@Model
final class Dog {
    var name: String = ""
    /// A small JPEG of the dog, made by `DogPhoto`.
    @Attribute(.externalStorage)
    var photoData: Data?
    /// The date when the dog became a retired dog, or nil if it still takes
    /// part in walks.
    var retiredAt: Date?
    /// Why the dog became a retired dog, or empty.
    var retirementReason: String = ""
    @Relationship(inverse: \Walk.dogs)
    var walks: [Walk]? = []
    @Relationship(inverse: \CompletedArea.dog)
    var completedAreas: [CompletedArea]? = []
    @Relationship(inverse: \CompletedStreet.dog)
    var completedStreets: [CompletedStreet]? = []

    init(name: String) {
        self.name = name
    }

    /// The dogs that the walker can choose when a walk starts.
    static let canJoinWalks = #Predicate<Dog> { $0.retiredAt == nil }

    var isRetired: Bool {
        retiredAt != nil
    }

    func retire(on date: Date, reason: String) {
        retiredAt = date
        retirementReason = reason
    }

    /// Makes a retired dog take part in walks again, for example after the
    /// user retired it by mistake.
    func unretire() {
        retiredAt = nil
        retirementReason = ""
    }
}
