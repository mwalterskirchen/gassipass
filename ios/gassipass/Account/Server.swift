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
}

/// The member row of an account on the server.
struct ServerMember: Equatable {
    var name: String
    /// The pack of the person, or nil for a person in no pack.
    var packID: UUID?
}
