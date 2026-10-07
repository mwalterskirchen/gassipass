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
    /// The number of invitations that this person accepted.
    private(set) var acceptedInvitations = 0

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

    /// The zone of the pack, which belongs to the pack owner of its members.
    func zoneID(of pack: Pack) -> CKRecordZone.ID? {
        let packOwner = members[pack.randomID]?.first(where: \.isPackOwner)
        return CKRecordZone.ID(zoneName: pack.randomID, ownerName: packOwner?.id ?? CKCurrentUserDefaultName)
    }

    func accept(_ metadata: CKShare.Metadata) {
        acceptedInvitations += 1
    }

    func remove(_ member: PackMember, from pack: Pack) {
        members[pack.randomID]?.removeAll { $0.id == member.id }
    }

    func leave(_ pack: Pack) {
        leftPacks.append(pack.randomID)
    }
}

extension CKShare.Metadata {
    /// The metadata of an invitation, with no values except the role and
    /// the status of the person who opens it. CloudKit makes no metadata in
    /// the tests, so it is decoded from an empty archive.
    static func empty(
        role: CKShare.ParticipantRole = .unknown, status: CKShare.ParticipantAcceptanceStatus = .unknown
    ) throws -> CKShare.Metadata {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("CKShareMetadata", for: EmptyArchive.self)
        archiver.encode(EmptyArchive(), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = false
        guard let metadata = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? CKShare.Metadata else {
            throw CocoaError(.coderReadCorrupt)
        }
        metadata.setValue(role.rawValue, forKey: "participantRole")
        metadata.setValue(status.rawValue, forKey: "participantStatus")
        return metadata
    }
}

/// An object that encodes nothing.
@objc(EmptyArchive) private final class EmptyArchive: NSObject, NSCoding {
    override init() {}
    init?(coder: NSCoder) {}
    func encode(with coder: NSCoder) {}
}
