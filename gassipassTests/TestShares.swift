//
//  TestShares.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 06.10.2026.
//

import CloudKit
@testable import gassipass

/// The shares of the packs in the tests, which never reach iCloud.
final class TestShares: PackShares {
    /// The shares by the random ID of their pack.
    private var shares: [String: CKShare] = [:]
    /// The members by the random ID of their pack.
    private var members: [String: [PackMember]]
    /// The random IDs of the packs that this person left.
    private(set) var leftPacks: [String] = []

    init(members: [String: [PackMember]] = [:]) {
        self.members = members
    }

    func share(of pack: Pack) -> CKShare? {
        shares[pack.randomID]
    }

    func makeShare(of pack: Pack) -> CKShare {
        let share = CKShare(recordZoneID: CKRecordZone.ID(zoneName: pack.randomID))
        shares[pack.randomID] = share
        return share
    }

    func save(_ share: CKShare, of pack: Pack) {}

    func members(of pack: Pack) -> [PackMember] {
        members[pack.randomID] ?? []
    }

    func accept(_ metadata: CKShare.Metadata) {}

    func remove(_ member: PackMember, from pack: Pack) {
        members[pack.randomID]?.removeAll { $0.id == member.id }
    }

    func leave(_ pack: Pack) {
        leftPacks.append(pack.randomID)
    }
}
