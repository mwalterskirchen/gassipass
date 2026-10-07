//
//  PinnedArea.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreData

/// An area that the user shows on the home screen, to follow its completion.
/// A pin belongs to the user, not to a dog, and it does not change what a
/// dog collects.
///
/// The entity follows the CloudKit rules (`Stores`). With two devices there
/// can be two pins for the same area. The area shows once, and unpinning
/// removes all of its pins.
@objc(PinnedArea)
final class PinnedArea: NSManagedObject {
    /// The BFS number of the area.
    @NSManaged var area: Int

    convenience init(area: Int, context: NSManagedObjectContext) {
        self.init(context: context)
        self.area = area
    }

    /// A request for all pins, in no order.
    static func all() -> NSFetchRequest<PinnedArea> {
        let request = NSFetchRequest<PinnedArea>(entityName: "PinnedArea")
        request.sortDescriptors = []
        return request
    }
}
