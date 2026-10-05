//
//  CompletedStreet.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreData

/// The permanent record that a dog has completed a street. It follows the
/// same rules as `CompletedArea`: nothing removes it, and with two devices
/// the earliest date counts.
@objc(CompletedStreet)
final class CompletedStreet: NSManagedObject {
    @NSManaged var dog: Dog?
    /// The BFS number of the area of the street.
    @NSManaged var area: Int
    /// The official name of the street.
    @NSManaged var street: String
    @NSManaged var completedAt: Date
    /// A random ID that decides which record stays when two records of
    /// the same dog and goal have the same date, so that every device keeps
    /// the same one. A record from before iCloud sync has an empty ID.
    @NSManaged var randomID: String

    convenience init(dog: Dog, street: Street.ID, completedAt: Date, context: NSManagedObjectContext) {
        self.init(context: context)
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
