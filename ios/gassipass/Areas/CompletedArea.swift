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
/// it (ADR 0002). With two phones there can be two records for the same dog
/// and area, and the earliest date counts (`Collections`).
extension CompletedArea {
    convenience init(dog: Dog, area: Int, completedAt: Date, context: ModelContext) {
        self.init(dog: dog, area: area, completedAt: completedAt)
        context.insert(self)
    }
}
