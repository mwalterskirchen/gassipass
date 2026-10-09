//
//  SupabaseServerTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Foundation
import Supabase
import SwiftData
import Testing
@testable import gassipass

/// The Supabase client of the app. Without an account it makes no request.
@MainActor
struct SupabaseServerTests {
    @Test func aPersonWithoutAnAccountMakesNoRequest() async throws {
        let container = try LocalStore.inMemory()
        try Packs(context: container.mainContext).addDog(named: "Bello")
        let server = SupabaseServer(client: LocalSupabase.client(session: RequestCounter.session))

        let account = Account(server: server, context: container.mainContext, defaults: LocalSupabase.emptyDefaults())
        await account.upload()

        #expect(!account.isSignedIn)
        #expect(RequestCounter.count == 0)
    }
}

/// The Supabase client of the app against the local Supabase of
/// `supabase start`. The tests do not run when it does not run.
@MainActor
@Suite(.enabled(if: LocalSupabase.isRunning, "The local Supabase does not run. Start it with `supabase start`."))
struct LocalSupabaseServerTests {
    @Test func theMemberAndThePackUploadAndASecondAccountCannotReadThePack() async throws {
        let anna = try await LocalSupabase.signedInServer()
        let ben = try await LocalSupabase.signedInServer()
        let packID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_790_000_000)

        try await anna.renameMember(to: "Anna")
        try await anna.createPack(id: packID, name: "Bellos Rudel", createdAt: createdAt)
        try await anna.createPack(id: packID, name: "Bellos Rudel", createdAt: createdAt)
        try await anna.renamePack(id: packID, to: "Annas Rudel")
        try await ben.renamePack(id: packID, to: "Bens Rudel")

        #expect(try await anna.member() == ServerMember(name: "Anna", packID: packID))
        #expect(try await ben.member() == ServerMember(name: "", packID: nil))
        let annasPacks: [LocalSupabase.PackRow] = try await anna.client.from("packs").select().execute().value
        let bensPacks: [LocalSupabase.PackRow] = try await ben.client.from("packs").select().execute().value
        #expect(annasPacks == [LocalSupabase.PackRow(id: packID, name: "Annas Rudel", createdAt: createdAt)])
        #expect(bensPacks.isEmpty)
    }
}

/// The local Supabase of `supabase start`, with the fixed keys that the
/// Supabase CLI gives every local project.
@MainActor
enum LocalSupabase {
    nonisolated static let url = URL(string: "http://127.0.0.1:54321")!
    nonisolated static let publishableKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
    nonisolated static let secretKey = "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz"

    nonisolated struct PackRow: Decodable, Equatable {
        var id: UUID
        var name: String
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, name
            case createdAt = "created_at"
        }
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
        let admin = SupabaseClient(
            supabaseURL: url, supabaseKey: secretKey,
            options: SupabaseClientOptions(auth: .init(storage: MemoryStorage(), autoRefreshToken: false)))
        let email = "\(UUID().uuidString.lowercased())@example.com"
        _ = try await admin.auth.admin.createUser(
            attributes: AdminUserAttributes(email: email, emailConfirm: true, password: "password"))
        let client = client()
        try await client.auth.signIn(email: email, password: "password")
        return SupabaseServer(client: client)
    }

    static func emptyDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SupabaseServerTests-\(UUID().uuidString)")!
    }
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

/// Counts the requests of its session, and answers none of them.
nonisolated final class RequestCounter: URLProtocol {
    nonisolated(unsafe) static var count = 0

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCounter.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.count += 1
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
