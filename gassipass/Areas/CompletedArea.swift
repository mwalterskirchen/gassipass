//
//  CompletedArea.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import SwiftData

/// The permanent record that a dog has completed an area. The app stores
/// each new record that the collection engine reports, and nothing removes
/// it (ADR 0002).
///
/// The model follows the CloudKit rules of SwiftData, like `Dog`. With two
/// devices there can be two records for the same dog and area. The earliest
/// date counts.
@Model
final class CompletedArea {
    var dog: Dog?
    /// The BFS number of the area.
    var area: Int = 0
    var completedAt: Date = Date.now

    init(dog: Dog, area: Int, completedAt: Date) {
        self.dog = dog
        self.area = area
        self.completedAt = completedAt
    }
}
