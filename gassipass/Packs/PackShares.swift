//
//  PackShares.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import CloudKit
import CoreData

/// The CloudKit shares of the packs, which tell the members of a pack.
/// `Packs` reads them from the container, and the tests give their own.
protocol PackShares {
    /// Whether the pack has a member besides the person on this phone.
    func hasOtherMembers(_ pack: Pack) throws -> Bool
}

/// The shares that the container keeps for the packs.
struct ContainerShares: PackShares {
    let container: NSPersistentCloudKitContainer

    func hasOtherMembers(_ pack: Pack) throws -> Bool {
        let share = try container.fetchShares(matching: [pack.objectID])[pack.objectID]
        // An invited person counts before they accept the invitation, so
        // that the invitation stays valid.
        return share?.participants.contains { $0.role != .owner } ?? false
    }
}
