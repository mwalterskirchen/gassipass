//
//  DogChoice.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import Observation
import SwiftData

/// The dog that the walker chooses. The home screen, the map and the
/// collection book all show the collection of this dog, so a choice on one
/// screen also counts on the others. The choice stays when the app starts
/// again.
@Observable
final class DogChoice {
    var chosenDogID: PersistentIdentifier? {
        didSet {
            defaults.set(try? JSONEncoder().encode(chosenDogID), forKey: Self.key)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "chosenDogID"

    /// Reads the stored choice. A stored choice that cannot be read counts
    /// as no choice.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        chosenDogID = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(PersistentIdentifier.self, from: $0) }
    }

    /// The chosen dog, else the first of the dogs. The first dog also counts
    /// when the chosen dog is not in the list any more.
    func shownDog(in dogs: [Dog]) -> Dog? {
        dogs.first { $0.persistentModelID == chosenDogID } ?? dogs.first
    }
}
