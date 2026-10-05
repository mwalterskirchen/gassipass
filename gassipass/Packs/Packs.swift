//
//  Packs.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import CoreData
import Observation
import OSLog
import SwiftUI

/// The packs of the person on this phone. It is the only part of the app
/// that knows about the two stores (ADR 0004). The rest of the app reads
/// the packs with `Pack.all()`, and makes and changes them only here.
///
/// A pack of this person lives in the private store. A pack that the person
/// joined lives in the shared store. A new object of a pack goes into the
/// store of that pack.
@Observable
final class Packs {
    @ObservationIgnored private let stores: Stores
    @ObservationIgnored private let shares: PackShares

    private static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "Packs")

    init(stores: Stores, shares: PackShares? = nil) {
        self.stores = stores
        self.shares = shares ?? ContainerShares(container: stores.container)
    }

    private var context: NSManagedObjectContext {
        stores.container.viewContext
    }

    /// All packs of this person, the first made first.
    func all() throws -> [Pack] {
        try context.fetch(Pack.all())
    }

    /// Adds a dog to the pack, or to the own pack of this person when the
    /// pack is nil, and saves it. A person in no pack first gets their own
    /// pack.
    @discardableResult
    func addDog(named name: String, photoData: Data? = nil, to pack: Pack? = nil) throws -> Dog {
        let pack = try pack ?? ownOrNewPack()
        let dog = Dog(name: name, context: context)
        context.assign(dog, to: store(of: pack))
        dog.photoData = photoData
        dog.pack = pack
        try context.save()
        return dog
    }

    /// Gives the pack a new name, and saves. An empty name gives the pack
    /// its default name.
    func rename(_ pack: Pack, to name: String) throws {
        pack.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    /// Moves the dogs from before the packs into the own pack of this
    /// person, and saves. A person who has such dogs and no own pack gets
    /// one. The first launch of the build with packs moves all dogs.
    func moveDogsWithoutPack() throws {
        // A dog in the shared store always came with its pack.
        let request = Dog.withoutPack()
        request.affectedStores = [stores.privateStore]
        let dogs = try context.fetch(request)
        guard !dogs.isEmpty else { return }
        let pack = try ownOrNewPack()
        for dog in dogs {
            dog.pack = pack
        }
        try context.save()
    }

    /// Merges the first packs of this person into the pack that was made
    /// first, and saves. Two phones of the same person can each make a first
    /// pack before they sync. A first pack is a pack of this person with no
    /// other members, so a pack that has another member or that this person
    /// joined never merges.
    ///
    /// Every phone keeps the same pack without talking to the other phones,
    /// because the order of `Pack.all()` breaks ties on the random ID.
    func mergeFirstPacks() throws {
        let request = Pack.all()
        request.affectedStores = [stores.privateStore]
        let ownPacks = try context.fetch(request)
        // A person with one pack has nothing to merge, so the app reads no
        // shares.
        guard ownPacks.count > 1 else { return }
        let firstPacks = try ownPacks.filter { try !shares.hasOtherMembers($0) }
        guard let kept = firstPacks.first else { return }
        for pack in firstPacks.dropFirst() {
            for dog in pack.dogs {
                dog.pack = kept
            }
            if kept.name.isEmpty {
                kept.name = pack.name
            }
            context.delete(pack)
        }
        try context.save()
    }

    /// Moves the dogs without a pack into a pack, and merges the first packs
    /// of this person. The app calls it at launch, and whenever sync brings a
    /// pack or a dog without a pack (`PackUpdates`). A failed step tries
    /// again at the next call.
    func tidyUp() {
        do {
            try moveDogsWithoutPack()
        } catch {
            Self.logger.error("The dogs cannot move into a pack: \(String(describing: error), privacy: .public)")
        }
        do {
            try mergeFirstPacks()
        } catch {
            Self.logger.error("The first packs cannot merge: \(String(describing: error), privacy: .public)")
        }
    }

    /// The first pack of this person, or a new pack when they have none.
    private func ownOrNewPack() throws -> Pack {
        let request = Pack.all()
        request.affectedStores = [stores.privateStore]
        request.fetchLimit = 1
        return try context.fetch(request).first ?? makeOwnPack()
    }

    /// The store of the pack. A new pack is not saved yet, and only the
    /// packs of this person are made on this phone.
    private func store(of pack: Pack) -> NSPersistentStore {
        pack.objectID.persistentStore ?? stores.privateStore
    }

    /// Makes a pack of this person in the private store.
    private func makeOwnPack() -> Pack {
        let pack = Pack(context: context)
        context.assign(pack, to: stores.privateStore)
        pack.createdAt = .now
        pack.randomID = UUID().uuidString
        return pack
    }
}

extension Packs {
    /// The packs of the empty in-memory stores, for previews.
    static let preview = Packs(stores: .preview)
}

/// Tidies the packs whenever sync brings a pack or a dog without a pack from
/// another phone, for example the first pack of the other phone of this
/// person. The app tidies them at launch too.
struct PackUpdates: ViewModifier {
    @Environment(Packs.self) private var packs
    @FetchRequest(fetchRequest: Pack.all()) private var allPacks
    @FetchRequest(fetchRequest: Dog.withoutPack()) private var dogsWithoutPack

    func body(content: Content) -> some View {
        content
            .task(id: packInput) {
                packs.tidyUp()
            }
    }

    /// What the tidy-up depends on. A change starts a new tidy-up.
    private var packInput: Set<NSManagedObjectID> {
        Set(allPacks.map(\.objectID)).union(dogsWithoutPack.map(\.objectID))
    }
}
