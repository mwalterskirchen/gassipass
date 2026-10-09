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

    @Test func eachKindOfRowUploadsAndASecondAccountCannotReadIt() async throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let packs = Packs(context: context)
        let photo = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let bello = try packs.addDog(named: "Bello", photoData: photo)
        let pack = try #require(bello.pack)
        let started = Date(timeIntervalSince1970: 1_790_000_000)
        let walk = Walk(startedAt: started, dogs: [bello], context: context)
        walk.store(Track(points: [
            TrackPoint(latitude: 47.4, longitude: 8.4, timestamp: started, horizontalAccuracy: 5),
        ]))
        walk.endedAt = started + 3_600
        let area = CompletedArea(dog: bello, area: 243, completedAt: started, context: context)
        let street = CompletedStreet(
            dog: bello, street: Street.ID(area: 243, name: "Zürcherstrasse"), completedAt: started, context: context)
        try context.save()
        let anna = try await LocalSupabase.signedInServer()
        let account = Account(server: anna, context: context, defaults: LocalSupabase.emptyDefaults())

        await account.renameMember(to: "Anna")

        let dogs: [LocalSupabase.DogRow] = try await anna.client.from("dogs").select().execute().value
        #expect(dogs == [LocalSupabase.DogRow(
            id: bello.id, packID: pack.id, name: "Bello", photoPath: ServerFile.dogPhoto(dog: bello.id, pack: pack.id).path,
            retiredAt: nil, deletedAt: nil)])
        let walks: [LocalSupabase.WalkRow] = try await anna.client.from("walks").select().execute().value
        // A walk with an empty member name gets the name of the pack owner.
        #expect(walks == [LocalSupabase.WalkRow(
            id: walk.id, packID: pack.id, startedAt: started, trackPath: ServerFile.track(walk: walk.id, pack: pack.id).path,
            memberName: "Anna", deletedAt: nil)])
        let walkDogs: [LocalSupabase.WalkDogRow] = try await anna.client.from("walk_dogs").select().execute().value
        #expect(walkDogs.map(\.dogID) == [bello.id])
        let areas: [LocalSupabase.RecordRow] = try await anna.client.from("completed_areas").select().execute().value
        #expect(areas.map(\.id) == [area.id])
        let streets: [LocalSupabase.RecordRow] = try await anna.client.from("completed_streets").select().execute().value
        #expect(streets.map(\.id) == [street.id])
        let storedPhoto = try await anna.client.storage.from("dog-photos")
            .download(path: ServerFile.dogPhoto(dog: bello.id, pack: pack.id).path)
        #expect(storedPhoto == photo)
        let storedTrack = try await anna.client.storage.from("tracks")
            .download(path: ServerFile.track(walk: walk.id, pack: pack.id).path)
        #expect(storedTrack == walk.trackData)
        #expect(account.waitingChanges == 0)

        let ben = try await LocalSupabase.signedInServer()
        let bensDogs: [LocalSupabase.DogRow] = try await ben.client.from("dogs").select().execute().value
        let bensWalks: [LocalSupabase.WalkRow] = try await ben.client.from("walks").select().execute().value
        #expect(bensDogs.isEmpty)
        #expect(bensWalks.isEmpty)
        await #expect(throws: (any Error).self) {
            try await ben.client.storage.from("tracks").download(path: ServerFile.track(walk: walk.id, pack: pack.id).path)
        }
    }

    @Test func aDeletedWalkAChangeToItsDogsAndARenamedRetiredDogUpload() async throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let packs = Packs(context: context)
        let bello = try packs.addDog(named: "Bello")
        let luna = try packs.addDog(named: "Luna")
        let walk = Walk(startedAt: .now - 3_600, dogs: [bello], context: context)
        walk.store(Track())
        walk.endedAt = .now
        let deleted = Walk(startedAt: .now - 3_600, dogs: [bello], context: context)
        deleted.store(Track())
        deleted.endedAt = .now
        try context.save()
        let anna = try await LocalSupabase.signedInServer()
        let account = Account(server: anna, context: context, defaults: LocalSupabase.emptyDefaults())
        await account.upload()

        bello.name = "Bello II"
        bello.retire(on: Date(timeIntervalSince1970: 1_790_000_000), reason: "Old age")
        bello.noteChange()
        walk.changeDogs(to: [luna])
        deleted.markDeleted()
        try context.save()
        await account.upload()

        let dog: LocalSupabase.DogRow = try await anna.client.from("dogs").select().eq("id", value: bello.id)
            .single().execute().value
        #expect(dog.name == "Bello II")
        #expect(dog.retiredAt == Date(timeIntervalSince1970: 1_790_000_000))
        let walkDogs: [LocalSupabase.WalkDogRow] = try await anna.client.from("walk_dogs").select()
            .eq("walk_id", value: walk.id).is("deleted_at", value: nil).execute().value
        #expect(walkDogs.map(\.dogID) == [luna.id])
        let deletedRow: LocalSupabase.WalkRow = try await anna.client.from("walks").select().eq("id", value: deleted.id)
            .single().execute().value
        #expect(deletedRow.deletedAt != nil)
        #expect(account.waitingChanges == 0)
    }

    /// Two phones can each store a record for the same dog and area.
    @Test func ofTwoCompletedRecordsForTheSameDogAndAreaOnlyTheEarliestStays() async throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let bello = try Packs(context: context).addDog(named: "Bello")
        let early = CompletedArea(dog: bello, area: 243, completedAt: Date(timeIntervalSince1970: 1_790_000_000), context: context)
        _ = CompletedArea(dog: bello, area: 243, completedAt: Date(timeIntervalSince1970: 1_790_100_000), context: context)
        try context.save()
        let anna = try await LocalSupabase.signedInServer()
        let account = Account(server: anna, context: context, defaults: LocalSupabase.emptyDefaults())

        await account.upload()

        let records: [LocalSupabase.RecordRow] = try await anna.client.from("completed_areas").select()
            .is("deleted_at", value: nil).execute().value
        #expect(records.map(\.id) == [early.id])
    }

    @Test func aWalkWhoseTrackFailedToUploadUploadsWithTheNextUpload() async throws {
        let container = try LocalStore.inMemory()
        let context = container.mainContext
        let bello = try Packs(context: context).addDog(named: "Bello")
        let walk = Walk(startedAt: .now - 3_600, dogs: [bello], context: context)
        walk.store(Track())
        walk.endedAt = .now
        try context.save()
        let anna = try await LocalSupabase.signedInServer()
        let server = FailingOnceServer(anna)
        let account = Account(server: server, context: context, defaults: LocalSupabase.emptyDefaults())

        await account.upload()
        let walksAfterFailure: [LocalSupabase.WalkRow] = try await anna.client.from("walks").select().execute().value
        let waitingAfterFailure = account.waitingChanges
        await account.upload()

        let walks: [LocalSupabase.WalkRow] = try await anna.client.from("walks").select().execute().value
        let walkDogs: [LocalSupabase.WalkDogRow] = try await anna.client.from("walk_dogs").select().execute().value
        #expect(walksAfterFailure.isEmpty)
        #expect(waitingAfterFailure == 2)
        #expect(walks.map(\.id) == [walk.id])
        #expect(walkDogs.map(\.dogID) == [bello.id])
        #expect(account.waitingChanges == 0)
    }
}

/// The real server, whose first file upload fails.
private final class FailingOnceServer: Server {
    private let server: any Server
    private var failsNextFileUpload = true

    init(_ server: any Server) {
        self.server = server
    }

    struct Failure: Error {}

    var isSignedIn: Bool { server.isSignedIn }

    func signIn(appleIDToken: String, nonce: String) async throws {
        try await server.signIn(appleIDToken: appleIDToken, nonce: nonce)
    }

    func member() async throws -> ServerMember { try await server.member() }
    func renameMember(to name: String) async throws { try await server.renameMember(to: name) }

    func createPack(id: UUID, name: String, createdAt: Date) async throws {
        try await server.createPack(id: id, name: name, createdAt: createdAt)
    }

    func renamePack(id: UUID, to name: String) async throws { try await server.renamePack(id: id, to: name) }
    func uploadDogs(_ dogs: [ServerDog]) async throws { try await server.uploadDogs(dogs) }
    func uploadWalks(_ walks: [ServerWalk]) async throws { try await server.uploadWalks(walks) }
    func uploadWalkDogs(_ walkDogs: [ServerWalkDog]) async throws { try await server.uploadWalkDogs(walkDogs) }

    func uploadCompletedAreas(_ records: [ServerCompletedArea]) async throws {
        try await server.uploadCompletedAreas(records)
    }

    func uploadCompletedStreets(_ records: [ServerCompletedStreet]) async throws {
        try await server.uploadCompletedStreets(records)
    }

    func uploadFile(_ data: Data, to file: ServerFile) async throws {
        if failsNextFileUpload {
            failsNextFileUpload = false
            throw Failure()
        }
        try await server.uploadFile(data, to: file)
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
        let admin = SupabaseClient(
            supabaseURL: url, supabaseKey: secretKey,
            options: SupabaseClientOptions(auth: .init(storage: MemoryStorage(), autoRefreshToken: false)))
        let email = "\(UUID().uuidString.lowercased())@example.com"
        _ = try await admin.auth.admin.createUser(
            attributes: AdminUserAttributes(email: email, emailConfirm: true, password: "password"))
        // Each account has its own session, so that no account gets a
        // response from the cache of another account.
        let client = client(session: URLSession(configuration: .ephemeral))
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
