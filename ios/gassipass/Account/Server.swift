//
//  Server.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Foundation

/// The server of the app (ADR 0006), as the account sees it.
protocol Server {
    /// Whether the phone keeps the session of an account. It makes no request.
    var isSignedIn: Bool { get }
    /// Signs in with the ID token of Sign in with Apple, and keeps the session.
    func signIn(appleIDToken: String, nonce: String) async throws
    /// Removes the session from the phone. The phone forgets the session
    /// also when the server cannot be reached.
    func signOut() async
    /// The member row of the account.
    func member() async throws -> ServerMember
    /// Gives the member row of the account a new name.
    func renameMember(to name: String) async throws
    /// Makes the pack on the server, with this person as its pack owner and
    /// member. A second call for the same pack changes nothing.
    func createPack(id: UUID, name: String, createdAt: Date) async throws
    /// Gives the pack a new name. Only a member of the pack can rename it.
    func renamePack(id: UUID, to name: String) async throws
    /// Writes the dogs, and replaces a stored dog with the same ID.
    func uploadDogs(_ dogs: [ServerDog]) async throws
    /// Writes the walks, and replaces a stored walk with the same ID.
    func uploadWalks(_ walks: [ServerWalk]) async throws
    /// Writes the dogs of walks. Their walks and dogs must be on the server.
    func uploadWalkDogs(_ walkDogs: [ServerWalkDog]) async throws
    /// Writes the completed records of areas. Their dogs must be on the
    /// server. The server keeps only the earliest record of each dog and area.
    func uploadCompletedAreas(_ records: [ServerCompletedArea]) async throws
    /// Writes the completed records of streets, with the same rules.
    func uploadCompletedStreets(_ records: [ServerCompletedStreet]) async throws
    /// Stores the file, and replaces a stored file at the same path.
    func uploadFile(_ data: Data, to file: ServerFile) async throws
    /// Deletes the file. A file that is not there is no failure.
    func deleteFile(_ file: ServerFile) async throws
    /// The pack, or nil when the person is no member of it.
    func pack(id: UUID) async throws -> ServerPack?
    /// The dogs of the pack that changed at the date or later, or all dogs
    /// of the pack for nil. A deleted row comes with its deletion time.
    func downloadDogs(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerDog>]
    /// The walks of the pack, with the same rules.
    func downloadWalks(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerWalk>]
    /// The dogs of the walks of the pack, with the same rules.
    func downloadWalkDogs(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerWalkDog>]
    /// The completed records of areas of the pack, with the same rules.
    func downloadCompletedAreas(
        of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerCompletedArea>]
    /// The completed records of streets of the pack, with the same rules.
    func downloadCompletedStreets(
        of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerCompletedStreet>]
    /// The content of the file.
    func downloadFile(_ file: ServerFile) async throws -> Data
    /// The members of the pack of the account, the pack owner first, or none
    /// for a person in no pack.
    func packMembers() async throws -> [PackMember]
    /// Makes an invitation to the pack of the account, and returns the token
    /// of its link. Only the pack owner can invite.
    func createInvitation() async throws -> String
    /// Whether the account can join with the invitation, and its pack.
    func checkInvitation(token: String) async throws -> Invitation
    /// Makes the account a member of the pack of the invitation, and uses up
    /// the invitation. The only member of a pack brings their dogs, with
    /// their walks and completed records, and their old pack disappears
    /// (ADR 0005). It returns `.joined`, or the state that keeps the person
    /// out.
    func joinPack(token: String) async throws -> InvitationState
    /// Whether the pack moved into the pack of the account, because its only
    /// member joined that pack from another phone.
    func hasMovedIntoPackOfAccount(pack: UUID) async throws -> Bool
    /// Takes the account out of its pack. The pack owner cannot leave. A
    /// person in no pack changes nothing.
    func leavePack() async throws
    /// Takes the member out of the pack of the account. Only the pack owner
    /// removes a member, and not themselves.
    func removeMember(id: UUID) async throws
    /// Whether the account has left the pack, or the pack owner removed it,
    /// and it is not in the pack again.
    func hasLeftPack(_ pack: UUID) async throws -> Bool
    /// The packs whose files the phone deletes before it deletes the
    /// account: for the only member of a pack, the pack and each pack that
    /// moved into it. A person in a pack with other members gets none.
    func packsDeletedWithAccount() async throws -> [UUID]
    /// Deletes every file in the folder of the pack in Storage.
    func deleteFiles(ofPack pack: UUID) async throws
    /// Deletes the account and its member row. The walks of the person stay
    /// with the dogs. When the pack has other members, the member who joined
    /// first becomes the pack owner. Otherwise the pack and everything in it
    /// is deleted, and its files must be deleted first. The phone keeps the
    /// session until `signOut()`.
    func deleteAccount() async throws
}

/// The member row of an account on the server.
struct ServerMember: Equatable {
    var name: String
    /// The pack of the person, or nil for a person in no pack.
    var packID: UUID?
}

/// A member of the pack, as the members of the pack see them.
nonisolated struct PackMember: Decodable, Equatable, Identifiable, Sendable {
    /// The ID of the account of the member.
    var id: UUID
    var name: String
    var isPackOwner: Bool
    /// Whether the member is the person on this phone.
    var isThisPerson: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case isPackOwner = "is_pack_owner"
        case isThisPerson = "is_caller"
    }
}

/// An invitation to a pack, as the person who opens its link sees it.
nonisolated struct Invitation: Decodable, Equatable, Sendable {
    var state: InvitationState
    /// The pack of the invitation, or nil for an unknown invitation.
    var packID: UUID?
    /// The name of the pack, or empty for a pack without a name of its own.
    var packName: String
    /// The name of the pack owner, or empty.
    var packOwnerName: String

    enum CodingKeys: String, CodingKey {
        case state
        case packID = "pack_id"
        case packName = "pack_name"
        case packOwnerName = "pack_owner_name"
    }

    init(state: InvitationState, packID: UUID?, packName: String, packOwnerName: String) {
        self.state = state
        self.packID = packID
        self.packName = packName
        self.packOwnerName = packOwnerName
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(InvitationState.self, forKey: .state)
        packID = try container.decodeIfPresent(UUID.self, forKey: .packID)
        packName = try container.decodeIfPresent(String.self, forKey: .packName) ?? ""
        packOwnerName = try container.decodeIfPresent(String.self, forKey: .packOwnerName) ?? ""
    }
}

/// Whether a person can join with an invitation. An invitation works once
/// and expires after 7 days, and a person is a member of at most one pack
/// (ADR 0005). The only member of a pack can join, and brings their dogs.
nonisolated enum InvitationState: String, Decodable, Sendable {
    /// The person can join.
    case open
    /// The person has joined with the invitation.
    case joined
    /// The person is a member of the pack already, for example the pack
    /// owner who opens their own invitation.
    case member
    /// Somebody has joined with the invitation.
    case used
    /// The invitation is older than 7 days.
    case expired
    /// The person is a member of another pack with other members.
    case inOtherPack = "in_other_pack"
    /// The server knows no invitation with the token.
    case unknown
}

/// The server refused a row, for example because it breaks a rule of its
/// table. The same row gets the same answer again, but the other rows of its
/// request can upload without it.
nonisolated struct RowRefused: Error {
    /// The answer of the server, if there is one.
    var underlying: (any Error)?
}
