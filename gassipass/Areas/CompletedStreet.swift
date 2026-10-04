//
//  CompletedStreet.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import SwiftData

/// The permanent record that a dog has completed a street. It follows the
/// same rules as `CompletedArea`: nothing removes it, and with two devices
/// the earliest date counts.
@Model
final class CompletedStreet {
    var dog: Dog?
    /// The BFS number of the area of the street.
    var area: Int = 0
    /// The official name of the street.
    var street: String = ""
    var completedAt: Date = Date.now
    /// A random ID that decides which record stays when two records of
    /// the same dog and goal have the same date, so that every device keeps
    /// the same one. A record from before iCloud sync has an empty ID.
    var randomID: String = ""

    init(dog: Dog, street: Street.ID, completedAt: Date) {
        self.dog = dog
        self.area = street.area
        self.street = street.name
        self.completedAt = completedAt
        randomID = UUID().uuidString
    }

    var streetID: Street.ID {
        Street.ID(area: area, name: street)
    }
}
