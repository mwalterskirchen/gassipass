//
//  LocalSupabase.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import Supabase
@testable import gassipass

/// The local Supabase of `supabase start`, with the fixed keys that the
/// Supabase CLI gives every local project.
@MainActor
enum LocalSupabase {
    nonisolated static let url = URL(string: "http://127.0.0.1:54321")!
    nonisolated static let publishableKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
    nonisolated static let secretKey = "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz"

    nonisolated struct DogRow: Decodable, Equatable {
        var id: UUID
        var packID: UUID
        var name: String
        var photoPath: String?
        var retiredAt: Date?
        var deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, name
            case packID = "pack_id"
            case photoPath = "photo_path"
            case retiredAt = "retired_at"
            case deletedAt = "deleted_at"
        }
    }

    nonisolated struct WalkRow: Decodable, Equatable {
        var id: UUID
        var packID: UUID
        var startedAt: Date
        var trackPath: String?
        var memberName: String
        var deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case packID = "pack_id"
            case startedAt = "started_at"
            case trackPath = "track_path"
            case memberName = "member_name"
            case deletedAt = "deleted_at"
        }
    }

    nonisolated struct WalkDogRow: Decodable, Equatable {
        var dogID: UUID

        enum CodingKeys: String, CodingKey {
            case dogID = "dog_id"
        }
    }

    nonisolated struct MemberRow: Decodable, Equatable {
        var accountID: UUID

        enum CodingKeys: String, CodingKey {
            case accountID = "account_id"
        }
    }

    /// A completed record of an area or a street.
    nonisolated struct RecordRow: Decodable, Equatable {
        var id: UUID
    }

    /// Whether the local Supabase answers.
    nonisolated static var isRunning: Bool {
        var request = URLRequest(url: url.appending(path: "auth/v1/health"), timeoutInterval: 1)
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        let answered = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var isRunning = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            isRunning = (response as? HTTPURLResponse)?.statusCode == 200
            answered.signal()
        }.resume()
        answered.wait()
        return isRunning
    }

    /// A client that keeps its session in memory, not in the keychain.
    static func client(session: URLSession = .shared) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: url, supabaseKey: publishableKey,
            options: SupabaseClientOptions(
                auth: .init(storage: MemoryStorage(), emitLocalSessionAsInitialSession: true),
                global: .init(session: session)))
    }

    /// The server, signed in with a new account. Sign in with Apple needs a
    /// real Apple ID, so the account signs in with a password.
    static func signedInServer() async throws -> SupabaseServer {
        try await signedInServer(email: newAccount())
    }

    /// The server, signed in with the account, as on one more phone.
    static func signedInServer(email: String) async throws -> SupabaseServer {
        // Each client has its own session, so that no account gets a
        // response from the cache of another account.
        let client = client(session: URLSession(configuration: .ephemeral))
        try await client.auth.signIn(email: email, password: "password")
        return SupabaseServer(client: client)
    }

    /// The files in the folder of the pack in each bucket, as the admin sees
    /// them.
    static func files(ofPack pack: UUID) async throws -> [String] {
        var names: [String] = []
        for bucket in ServerFile.Bucket.allCases {
            let files = try await admin.storage.from(bucket.rawValue).list(path: ServerFile.folder(of: pack))
            names += files.map { "\(bucket.rawValue)/\($0.name)" }
        }
        return names
    }

    /// Makes a new account, and returns its email address.
    static func newAccount() async throws -> String {
        let email = "\(UUID().uuidString.lowercased())@example.com"
        _ = try await admin.auth.admin.createUser(
            attributes: AdminUserAttributes(email: email, emailConfirm: true, password: "password"))
        return email
    }

    /// A client with the secret key, which row-level security does not stop.
    /// It lives as long as the tests, because the SDK stops the app when a
    /// client is released during one of its requests.
    static let admin = SupabaseClient(
        supabaseURL: url, supabaseKey: secretKey,
        options: SupabaseClientOptions(auth: .init(storage: MemoryStorage(), autoRefreshToken: false)))
}

nonisolated private final class MemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()

    func store(key: String, value: Data) throws {
        lock.withLock { values[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func remove(key: String) throws {
        _ = lock.withLock { values.removeValue(forKey: key) }
    }
}
