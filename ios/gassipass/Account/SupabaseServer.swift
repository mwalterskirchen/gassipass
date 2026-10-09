//
//  SupabaseServer.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Foundation
import Supabase

/// The Supabase project of the build (ADR 0006). The scheme "gassipass"
/// talks to the development project, and the scheme "gassipass Production"
/// and TestFlight talk to production. The tables and their row-level
/// security are in `supabase/migrations/`.
///
/// The client keeps the session in the keychain. Without a session it makes
/// no request.
final class SupabaseServer: Server {
    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// The project in the Info.plist of the build, or nil when the build has
    /// no Supabase keys (see `ios/Config/Supabase.example.xcconfig`).
    static func ofThisBuild(bundle: Bundle = .main) -> SupabaseServer? {
        guard let address = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let url = URL(string: address), url.host() != nil,
            let key = bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String, !key.isEmpty
        else { return nil }
        let options = SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        return SupabaseServer(client: SupabaseClient(supabaseURL: url, supabaseKey: key, options: options))
    }

    var isSignedIn: Bool {
        client.auth.currentSession != nil
    }

    func signIn(appleIDToken: String, nonce: String) async throws {
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: appleIDToken, nonce: nonce))
    }

    func member() async throws -> ServerMember {
        // Row-level security shows only the member row of this account.
        let row: MemberRow = try await client.from("members").select("name, pack_id").single().execute().value
        return ServerMember(name: row.name, packID: row.packID)
    }

    func renameMember(to name: String) async throws {
        try await client.from("members").update(["name": name]).eq("account_id", value: try accountID()).execute()
    }

    func createPack(id: UUID, name: String, createdAt: Date) async throws {
        try await client.rpc("create_pack", params: CreatePack(packID: id, packName: name, packCreatedAt: createdAt))
            .execute()
    }

    func renamePack(id: UUID, to name: String) async throws {
        try await client.from("packs").update(["name": name]).eq("id", value: id).execute()
    }

    private func accountID() throws -> UUID {
        guard let user = client.auth.currentUser else { throw AuthError.sessionMissing }
        return user.id
    }
}

nonisolated private struct MemberRow: Decodable {
    var name: String
    var packID: UUID?

    enum CodingKeys: String, CodingKey {
        case name
        case packID = "pack_id"
    }
}

nonisolated private struct CreatePack: Encodable {
    var packID: UUID
    var packName: String
    var packCreatedAt: Date

    enum CodingKeys: String, CodingKey {
        case packID = "pack_id"
        case packName = "pack_name"
        case packCreatedAt = "pack_created_at"
    }
}
