//
//  SupabaseServer.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Foundation
import Supabase

/// The Supabase project of the build (ADR 0006). The scheme "gassipass"
/// talks to the development project. The scheme "gassipass Production" and
/// TestFlight talk to production. The tables and their row-level security
/// are in `supabase/migrations/`.
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

    func signOut() async {
        // The client removes the session from the keychain before it tells
        // the server, so a failed request leaves the phone signed out.
        try? await client.auth.signOut(scope: .local)
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

    func updatePack(id: UUID, with change: ServerPackChange) async throws {
        try await client.from("packs").update(change).eq("id", value: id).execute()
    }

    func uploadDogs(_ dogs: [ServerDog]) async throws {
        try await upsert(dogs)
    }

    func uploadWalks(_ walks: [ServerWalk]) async throws {
        try await upsert(walks)
    }

    func uploadWalkDogs(_ walkDogs: [ServerWalkDog]) async throws {
        try await upsert(walkDogs)
    }

    func uploadCompletedAreas(_ records: [ServerCompletedArea]) async throws {
        try await upsert(records)
    }

    func uploadCompletedStreets(_ records: [ServerCompletedStreet]) async throws {
        try await upsert(records)
    }

    func uploadAreaSteps(_ steps: [ServerAreaStep]) async throws {
        try await upsert(steps)
    }

    func uploadCompletedRings(_ rings: [ServerCompletedRing]) async throws {
        try await upsert(rings)
    }

    func uploadWeeklyGoals(_ sets: [ServerGoalSet]) async throws {
        try await upsert(sets)
    }

    func uploadFile(_ data: Data, to file: ServerFile) async throws {
        try await client.storage.from(file.bucket.rawValue)
            .upload(file.path, data: data, options: FileOptions(contentType: file.contentType, upsert: true))
    }

    func deleteFile(_ file: ServerFile) async throws {
        try await client.storage.from(file.bucket.rawValue).remove(paths: [file.path])
    }

    func pack(id: UUID) async throws -> ServerPack? {
        // Row-level security shows only the pack of the person.
        let packs: [ServerPack] = try await client.from("packs").select("id, name, created_at, home_latitude, home_longitude, home_set_at").eq("id", value: id)
            .execute().value
        return packs.first
    }

    func downloadDogs(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerDog>] {
        try await download(of: pack, changedSince: date)
    }

    func downloadWalks(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerWalk>] {
        try await download(of: pack, changedSince: date)
    }

    func downloadWalkDogs(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerWalkDog>] {
        try await download(of: pack, changedSince: date)
    }

    func downloadCompletedAreas(
        of pack: UUID, changedSince date: Date?
    ) async throws -> [Downloaded<ServerCompletedArea>] {
        try await download(of: pack, changedSince: date)
    }

    func downloadCompletedStreets(
        of pack: UUID, changedSince date: Date?
    ) async throws -> [Downloaded<ServerCompletedStreet>] {
        try await download(of: pack, changedSince: date)
    }

    func downloadAreaSteps(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerAreaStep>] {
        try await download(of: pack, changedSince: date)
    }

    func downloadCompletedRings(
        of pack: UUID, changedSince date: Date?
    ) async throws -> [Downloaded<ServerCompletedRing>] {
        try await download(of: pack, changedSince: date)
    }

    func downloadWeeklyGoals(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<ServerGoalSet>] {
        try await download(of: pack, changedSince: date)
    }

    func downloadFile(_ file: ServerFile) async throws -> Data {
        // The URL session keeps a downloaded file for an hour. The content
        // at a path never changes, so the kept file is never old.
        do {
            return try await client.storage.from(file.bucket.rawValue).download(path: file.path)
        } catch let error as StorageError where error.statusCode == "404" {
            throw FileMissing()
        }
    }

    func packMembers() async throws -> [PackMember] {
        try await client.rpc("pack_members").execute().value
    }

    func createInvitation() async throws -> String {
        try await client.rpc("create_invitation").execute().value
    }

    func checkInvitation(token: String) async throws -> Invitation {
        try await client.rpc("check_invitation", params: ["token": token]).single().execute().value
    }

    func joinPack(token: String) async throws -> InvitationState {
        try await client.rpc("join_pack", params: ["token": token]).execute().value
    }

    func hasMovedIntoPackOfAccount(pack: UUID) async throws -> Bool {
        try await client.rpc("has_moved_into_pack_of_caller", params: ["pack_id": pack]).execute().value
    }

    func leavePack() async throws {
        try await client.rpc("leave_pack").execute()
    }

    func removeMember(id: UUID) async throws {
        try await client.rpc("remove_member", params: ["member_id": id]).execute()
    }

    func hasLeftPack(_ pack: UUID) async throws -> Bool {
        try await client.rpc("has_left_pack", params: ["pack_id": pack]).execute().value
    }

    func packsDeletedWithAccount() async throws -> [UUID] {
        try await client.rpc("packs_deleted_with_account").execute().value
    }

    /// Storage lists at most a page of files for each request, so the files
    /// go away a page at a time.
    func deleteFiles(ofPack pack: UUID) async throws {
        let folder = ServerFile.folder(of: pack)
        for bucket in ServerFile.Bucket.allCases {
            let storage = client.storage.from(bucket.rawValue)
            while true {
                let files = try await storage.list(path: folder, options: SearchOptions(limit: Self.pageSize))
                guard !files.isEmpty else { break }
                let removed = try await storage.remove(paths: files.map { "\(folder)/\($0.name)" })
                // Row-level security can keep a file without a failure, and
                // the next page would list it again.
                guard removed.count == files.count else { throw FilesKept(folder: folder) }
            }
        }
    }

    func deleteAccount() async throws {
        try await client.rpc("delete_account").execute()
    }

    /// The rows of the pack that changed at the date or later.
    ///
    /// PostgREST gives at most `pageSize` rows for each request, so the rows
    /// come in pages, in the order of their change and their ID. Each page
    /// asks for the rows after the last row of the page before. Pages by
    /// position could skip a row that changes during the download. A row
    /// that changes during the download can come twice, and only its newer
    /// change counts.
    private func download<Row: ServerRow>(of pack: UUID, changedSince date: Date?) async throws -> [Downloaded<Row>] {
        var rows: [Downloaded<Row>] = []
        var indexByID: [UUID: Int] = [:]
        var last: RowOfPage<Row>?
        while true {
            var query = client.from(Row.table.rawValue).select().eq("pack_id", value: pack)
            if let date {
                query = query.gte("changed_at", value: date)
            }
            if let last {
                let changedAt = "\"\(last.changedAtText)\""
                query = query.or(
                    "changed_at.gt.\(changedAt),and(changed_at.eq.\(changedAt),id.gt.\(last.downloaded.row.id))")
            }
            let page: [RowOfPage<Row>] = try await query.order("changed_at").order("id").limit(Self.pageSize)
                .execute().value
            for rowOfPage in page {
                let downloaded = rowOfPage.downloaded
                if let index = indexByID[downloaded.row.id] {
                    rows[index] = downloaded
                } else {
                    indexByID[downloaded.row.id] = rows.count
                    rows.append(downloaded)
                }
            }
            guard page.count == Self.pageSize else { return rows }
            last = page.last
        }
    }

    /// The number of rows that PostgREST gives for one request
    /// (`max_rows` in `supabase/config.toml`), and of files that a deletion
    /// lists at a time.
    private static let pageSize = 1000

    /// Writes the rows, and replaces the stored rows with the same IDs. A row
    /// that breaks a rule of the table, or of row-level security, throws
    /// `RowRefused`.
    private func upsert<Row: ServerRow>(_ rows: [Row]) async throws {
        guard !rows.isEmpty else { return }
        do {
            try await client.from(Row.table.rawValue).upsert(rows, onConflict: "id", returning: .minimal).execute()
        } catch let error as PostgrestError where Self.refusesRow(error) {
            throw RowRefused(underlying: error)
        }
    }

    /// Whether Postgres refused a row: a data exception (class 22), a broken
    /// constraint (class 23), or row-level security (42501). An expired
    /// session has a code of PostgREST, so it is no refusal.
    private static func refusesRow(_ error: PostgrestError) -> Bool {
        guard let code = error.code else { return false }
        return code.hasPrefix("22") || code.hasPrefix("23") || code == "42501"
    }

    private func accountID() throws -> UUID {
        guard let user = client.auth.currentUser else { throw AuthError.sessionMissing }
        return user.id
    }
}

/// A row of a page of a download.
nonisolated private struct RowOfPage<Row: ServerRow>: Decodable {
    var downloaded: Downloaded<Row>
    /// The time of the change as Postgres writes it, with microseconds. A
    /// date in a filter has only milliseconds, so the next page compares
    /// this text.
    var changedAtText: String

    private enum CodingKeys: String, CodingKey {
        case changedAt = "changed_at"
    }

    init(from decoder: any Decoder) throws {
        downloaded = try Downloaded(from: decoder)
        changedAtText = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .changedAt)
    }
}

/// Storage kept files of the folder that the phone deleted.
nonisolated struct FilesKept: Error {
    var folder: String
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
