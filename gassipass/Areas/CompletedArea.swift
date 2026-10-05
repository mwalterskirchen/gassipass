//
//  CompletedArea.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreData

/// The permanent record that a dog has completed an area. The app stores
/// each new record that the collection engine reports, and nothing removes
/// it (ADR 0002).
///
/// The entity follows the CloudKit rules (`Stores`). With two devices there
/// can be two records for the same dog and area. The earliest date counts.
@objc(CompletedArea)
final class CompletedArea: NSManagedObject {
    @NSManaged var dog: Dog?
    /// The BFS number of the area.
    @NSManaged var area: Int
    @NSManaged var completedAt: Date
    /// A random ID that decides which record stays when two records of
    /// the same dog and goal have the same date, so that every device keeps
    /// the same one. A record from before iCloud sync has an empty ID.
    @NSManaged var randomID: String

    convenience init(dog: Dog, area: Int, completedAt: Date, context: NSManagedObjectContext) {
        self.init(context: context)
        self.dog = dog
        self.area = area
        self.completedAt = completedAt
        randomID = UUID().uuidString
    }
}
