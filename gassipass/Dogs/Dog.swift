//
//  Dog.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreData

/// The owner of a collection. Each dog has its own collection and its own
/// completions.
///
/// The app never deletes a dog. A dog that no longer takes part in walks
/// becomes a retired dog, and its collection, completions and completed
/// records stay.
///
/// The entity in the Core Data model follows the CloudKit rules (`Stores`).
@objc(Dog)
final class Dog: NSManagedObject {
    @NSManaged var name: String
    /// A small JPEG of the dog, made by `DogPhoto`.
    @NSManaged var photoData: Data?
    /// The date when the dog became a retired dog, or nil if it still takes
    /// part in walks.
    @NSManaged var retiredAt: Date?
    /// Why the dog became a retired dog, or empty.
    @NSManaged var retirementReason: String
    @NSManaged var walks: Set<Walk>
    @NSManaged var completedAreas: Set<CompletedArea>
    @NSManaged var completedStreets: Set<CompletedStreet>
    /// The pack of the dog. Only a dog from before the packs has none, until
    /// `Packs` moves it into a pack at launch.
    @NSManaged var pack: Pack?

    convenience init(name: String, context: NSManagedObjectContext) {
        self.init(context: context)
        self.name = name
    }

    /// A request for all dogs, sorted by name in the order of the Finder.
    static func all() -> NSFetchRequest<Dog> {
        let request = NSFetchRequest<Dog>(entityName: "Dog")
        request.sortDescriptors = [NSSortDescriptor(
            key: #keyPath(Dog.name), ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))]
        return request
    }

    /// A request for the dogs from before the packs, which have no pack yet.
    static func withoutPack() -> NSFetchRequest<Dog> {
        let request = all()
        request.predicate = NSPredicate(format: "pack == nil")
        return request
    }

    /// A request for the dogs that the walker can choose when a walk starts,
    /// sorted by name.
    static func canJoinWalks() -> NSFetchRequest<Dog> {
        let request = all()
        request.predicate = NSPredicate(format: "retiredAt == nil")
        return request
    }

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

/// The identity of the object, which stays the same when its object ID
/// changes from a temporary to a permanent ID at the first save.
extension Dog: Identifiable {}
