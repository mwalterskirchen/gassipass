//
//  Packs.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import CoreData
import Observation

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

    init(stores: Stores) {
        self.stores = stores
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
    /// one. The app calls it at launch, so the first launch of the build with
    /// packs moves all dogs.
    func moveDogsWithoutPack() throws {
        // A dog in the shared store always came with its pack.
        let request = Dog.all()
        request.predicate = NSPredicate(format: "pack == nil")
        request.affectedStores = [stores.privateStore]
        let dogs = try context.fetch(request)
        guard !dogs.isEmpty else { return }
        let pack = try ownOrNewPack()
        for dog in dogs {
            dog.pack = pack
        }
        try context.save()
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
