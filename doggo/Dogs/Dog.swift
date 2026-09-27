//
//  Dog.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import SwiftData

/// The owner of a collection. Each dog has its own collection and its own
/// completions.
///
/// The model follows the CloudKit rules of SwiftData, so that sync can start
/// without a migration: every attribute has a default value, every
/// relationship is optional and has an inverse, and nothing is unique.
@Model
final class Dog {
    var name: String = ""
    @Relationship(inverse: \Walk.dogs)
    var walks: [Walk]? = []
    @Relationship(inverse: \CompletedArea.dog)
    var completedAreas: [CompletedArea]? = []
    @Relationship(inverse: \CompletedStreet.dog)
    var completedStreets: [CompletedStreet]? = []

    init(name: String) {
        self.name = name
    }
}
