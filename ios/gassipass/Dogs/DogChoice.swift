//
//  DogChoice.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import Observation

/// The dog that the walker chooses. The home screen, the map and the
/// collection book all show the collection of this dog, so a choice on one
/// screen also counts on the others. The choice stays when the app starts
/// again.
@Observable
final class DogChoice {
    /// The stable ID of the chosen dog.
    private var chosenDogID: UUID? {
        didSet {
            defaults.set(chosenDogID?.uuidString, forKey: Self.key)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "chosenDog"
    /// The key of the choice of the builds with Core Data.
    private static let coreDataKey = "chosenDogURI"

    /// Reads the stored choice. A stored choice that cannot be read counts
    /// as no choice.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        chosenDogID = defaults.string(forKey: Self.key).flatMap(UUID.init(uuidString:))
    }

    /// Chooses the dog with the stable ID, or no dog.
    func choose(_ dog: UUID?) {
        chosenDogID = dog
    }

    /// The chosen dog, else the first of the dogs. The first dog also counts
    /// when the chosen dog is not in the list any more.
    func shownDog(in dogs: some Collection<Dog>) -> Dog? {
        dogs.first { $0.id == chosenDogID } ?? dogs.first
    }

    /// Carries the choice of the builds with Core Data over to the copy of
    /// the dog, once. The old choice holds the URI of the Core Data object ID
    /// of the dog, and the copy tells the new ID of each dog by that URI.
    static func carryOver(dogIDs: [URL: UUID], in defaults: UserDefaults) {
        guard let uri = defaults.url(forKey: coreDataKey) else { return }
        defaults.removeObject(forKey: coreDataKey)
        if let id = dogIDs[uri] {
            defaults.set(id.uuidString, forKey: key)
        }
    }
}
