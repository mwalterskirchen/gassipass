//
//  Packs.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import Foundation
import Observation
import OSLog
import SwiftData

/// The pack of the person on this phone. The rest of the app reads the packs
/// with `Pack.all()`, and makes and changes them here. Only `Account` and
/// `PackDownload` change them for the server (ADR 0006).
///
/// A person is a member of at most one pack (ADR 0005). Without an account,
/// the pack exists only on this phone, and this person is its pack owner.
@Observable
final class Packs {
    @ObservationIgnored private let context: ModelContext

    private static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "Packs")

    init(context: ModelContext) {
        self.context = context
    }

    /// All packs of this person, the first made first.
    func all() throws -> [Pack] {
        try context.fetch(Pack.all())
    }

    /// Adds a dog to the pack of this person, and saves it. A person in no
    /// pack first gets their own pack.
    @discardableResult
    func addDog(named name: String, photoData: Data? = nil) throws -> Dog {
        let pack = try Pack.ofThisPhone(in: context) ?? makeOwnPack()
        let dog = Dog(name: name, context: context)
        dog.photoData = photoData
        dog.pack = pack
        try context.save()
        return dog
    }

    /// Gives the pack a new name, and saves. An empty name gives the pack
    /// its default name.
    func rename(_ pack: Pack, to name: String) throws {
        pack.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pack.noteChange()
        try context.save()
    }

    /// Sets the home base of the pack, and saves. The account uploads it
    /// after the save.
    func setHomeBase(_ homeBase: HomeBase, of pack: Pack) throws {
        pack.setHomeBase(homeBase, at: .now)
        try context.save()
    }

    /// Moves the dogs from before the packs into the first pack of this
    /// person, and saves. A person who has such dogs and no pack gets one.
    /// The app calls it at launch, and a failed move tries again at the next
    /// launch.
    func moveDogsWithoutPack() {
        do {
            let dogs = try context.fetch(Dog.withoutPack())
            guard !dogs.isEmpty else { return }
            let pack = try Pack.ofThisPhone(in: context) ?? makeOwnPack()
            for dog in dogs {
                dog.pack = pack
                dog.noteChange()
            }
            try context.save()
        } catch {
            Self.logger.error("The dogs cannot move into a pack: \(String(describing: error), privacy: .public)")
        }
    }

    /// Makes a pack of this person.
    private func makeOwnPack() -> Pack {
        let pack = Pack(name: "", createdAt: .now)
        context.insert(pack)
        return pack
    }
}

extension Packs {
    /// The packs of the empty in-memory store, for previews.
    static let preview = Packs(context: .preview)
}
