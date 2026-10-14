//
//  TestStores.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import Foundation
import SwiftData
import Testing
@testable import gassipass

extension ModelContainer {
    /// A second context on the store, which sees only what was saved.
    func newContext() -> ModelContext {
        ModelContext(self)
    }
}

extension ModelContext {
    /// All rows of the model, with the values that are in the store now.
    func fetchAll<Model: PersistentModel>(_ type: Model.Type) throws -> [Model] {
        try fetch(FetchDescriptor<Model>())
    }
}

/// Empty user defaults that no other test shares.
func emptyDefaults() -> UserDefaults {
    UserDefaults(suiteName: "gassipassTests-\(UUID().uuidString)")!
}

/// A phone with its own store, its own user defaults and its own account,
/// which talks to the server.
@MainActor
struct Phone<S: Server> {
    let container: ModelContainer
    let context: ModelContext
    let packs: Packs
    let defaults: UserDefaults
    let server: S
    let account: Account

    init(server: S) throws {
        container = try LocalStore.inMemory()
        context = container.mainContext
        packs = Packs(context: context)
        defaults = emptyDefaults()
        self.server = server
        account = Account(server: server, context: context, defaults: defaults)
    }

    /// Signs in. Apple gives the name of the person only at the first
    /// sign-in.
    func signIn(givenName: String? = nil) async throws {
        try await account.signIn(with: AppleCredential(idToken: "token", nonce: "nonce", givenName: givenName))
    }

    func dogs() throws -> [Dog] {
        try context.fetch(Dog.all())
    }

    func walks() throws -> [Walk] {
        try context.fetch(Walk.ended())
    }

    func dog(_ id: UUID) throws -> Dog {
        try #require(try context.fetchAll(Dog.self).first { $0.id == id })
    }

    func walk(_ id: UUID) throws -> Walk {
        try #require(try context.fetchAll(Walk.self).first { $0.id == id })
    }

    /// Records a walk of an hour with the dogs, and saves it. Without a
    /// track, the walk gets a short one.
    @discardableResult
    func recordWalk(
        startedAt start: Date = .now - 3_600, dogs: [Dog], track: Track? = nil, memberName: String = ""
    ) throws -> Walk {
        let walk = Walk(startedAt: start, dogs: dogs, context: context)
        walk.store(track ?? Track(points: [
            TrackPoint(latitude: 47.4, longitude: 8.4, timestamp: start, horizontalAccuracy: 5),
            TrackPoint(latitude: 47.401, longitude: 8.4, timestamp: start + 60, horizontalAccuracy: 5),
        ]))
        walk.endedAt = start + 3_600
        walk.memberName = memberName
        try context.save()
        return walk
    }
}
