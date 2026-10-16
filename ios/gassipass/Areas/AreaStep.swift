//
//  AreaStep.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import Foundation
import SwiftData

/// The permanent record that a dog has reached a step of the stamp of an
/// area. It follows the same rules as `CompletedArea`.
extension AreaStep {
    convenience init(dog: Dog, area: Int, step: StampStep, reachedAt: Date, context: ModelContext) {
        self.init(dogID: dog.id, area: area, step: step.rawValue, reachedAt: reachedAt)
        context.insert(self)
    }

    /// The step of the stamp, or nil for a step that this build does not know.
    var stampStep: StampStep? {
        StampStep(rawValue: step).flatMap { StampStep.areaSteps.contains($0) ? $0 : nil }
    }
}
