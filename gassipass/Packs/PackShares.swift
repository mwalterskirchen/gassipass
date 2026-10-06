//
//  PackShares.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import CloudKit
import CoreData

/// The CloudKit shares of the packs. One pack is one share, and the share
/// lists the members of the pack. `Packs` reads and makes them in the
/// container, and the tests give their own.
protocol PackShares {
    /// The share of the pack, or nil when the pack has none.
    func share(of pack: Pack) throws -> CKShare?
    /// Shares the pack, with its dogs, their walks and their completed
    /// records, in a new share.
    func makeShare(of pack: Pack) async throws -> CKShare
    /// Saves a change of the share to iCloud.
    func save(_ share: CKShare, of pack: Pack) async throws
    /// The members of the pack, from its share. A pack with no share has
    /// no members to list.
    func members(of pack: Pack) throws -> [PackMember]
    /// Accepts an invitation. The pack of the invitation goes into the
    /// shared store.
    func accept(_ metadata: CKShare.Metadata) async throws
}

/// A member of a pack, as the share of the pack lists them.
struct PackMember: Hashable {
    /// The name from the iCloud identity of the member, or nil when iCloud
    /// does not tell it.
    var name: PersonNameComponents?
    var isPackOwner: Bool
    /// Whether the member is the person on this phone.
    var isThisPerson: Bool
    /// Whether the member has accepted the invitation.
    var hasAccepted: Bool

    /// The first name of the member, or nil when iCloud does not tell it.
    var firstName: String? {
        guard let givenName = name?.givenName, !givenName.isEmpty else { return nil }
        return givenName
    }
}

/// The shares that the container keeps for the packs.
struct ContainerShares: PackShares {
    let stores: Stores

    private var container: NSPersistentCloudKitContainer {
        stores.container
    }

    func share(of pack: Pack) throws -> CKShare? {
        try container.fetchShares(matching: [pack.objectID])[pack.objectID]
    }

    func makeShare(of pack: Pack) async throws -> CKShare {
        try await container.share([pack], to: nil).1
    }

    func save(_ share: CKShare, of pack: Pack) async throws {
        guard let store = pack.objectID.persistentStore else { return }
        try await container.persistUpdatedShare(share, in: store)
    }

    func members(of pack: Pack) throws -> [PackMember] {
        guard let share = try share(of: pack) else { return [] }
        let thisPerson = share.currentUserParticipant
        // A member who left or was removed stays in the share with the
        // status "removed".
        return share.participants.filter { $0.acceptanceStatus != .removed }.map { participant in
            PackMember(
                name: participant.userIdentity.nameComponents,
                isPackOwner: participant.role == .owner,
                isThisPerson: participant == thisPerson,
                hasAccepted: participant.acceptanceStatus == .accepted)
        }
    }

    func accept(_ metadata: CKShare.Metadata) async throws {
        try await container.acceptShareInvitations(from: [metadata], into: stores.sharedStore)
    }
}
