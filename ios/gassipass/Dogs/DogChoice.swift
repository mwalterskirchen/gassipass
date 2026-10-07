//
//  DogChoice.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import CoreData
import Observation

/// The dog that the walker chooses. The home screen, the map and the
/// collection book all show the collection of this dog, so a choice on one
/// screen also counts on the others. The choice stays when the app starts
/// again.
@Observable
final class DogChoice {
    /// The URI of the object ID of the chosen dog, which stays the same when
    /// the app starts again.
    private var chosenDogURI: URL? {
        didSet {
            defaults.set(chosenDogURI, forKey: Self.key)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "chosenDogURI"
    /// The key of the choice of the builds with SwiftData.
    private static let swiftDataKey = "chosenDogID"

    /// Reads the stored choice. A stored choice that cannot be read counts
    /// as no choice.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        chosenDogURI = defaults.url(forKey: Self.key)
        if let data = defaults.data(forKey: Self.swiftDataKey) {
            defaults.removeObject(forKey: Self.swiftDataKey)
            if chosenDogURI == nil {
                chosenDogURI = try? JSONDecoder().decode(SwiftDataChoice.self, from: data).implementation.uriRepresentation
            }
        }
    }

    /// Chooses the dog with the ID. The ID must be permanent, so the dog
    /// must be saved.
    func choose(_ dog: NSManagedObjectID?) {
        chosenDogURI = dog?.uriRepresentation()
    }

    /// The chosen dog, else the first of the dogs. The first dog also counts
    /// when the chosen dog is not in the list any more.
    func shownDog(in dogs: some Collection<Dog>) -> Dog? {
        dogs.first { $0.objectID.uriRepresentation() == chosenDogURI } ?? dogs.first
    }
}

/// The part of a JSON-encoded SwiftData `PersistentIdentifier` that names the
/// object in Core Data. Core Data opens the store of SwiftData, so the URI
/// still names the same dog.
nonisolated private struct SwiftDataChoice: Decodable {
    struct Implementation: Decodable {
        let uriRepresentation: URL
    }

    let implementation: Implementation
}
