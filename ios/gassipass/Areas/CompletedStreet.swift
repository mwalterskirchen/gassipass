//
//  CompletedStreet.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import SwiftData

/// The permanent record that a dog has completed a street. It follows the
/// same rules as `CompletedArea`.
extension CompletedStreet {
    convenience init(dog: Dog, street: Street.ID, completedAt: Date, context: ModelContext) {
        self.init(dog: dog, street: street, completedAt: completedAt)
        context.insert(self)
    }

    var streetID: Street.ID {
        Street.ID(area: area, name: street)
    }
}
