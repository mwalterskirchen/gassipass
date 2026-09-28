//
//  DogChoice.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Observation
import SwiftData

/// The dog that the walker chooses. The home screen, the map and the
/// collection book all show the collection of this dog, so a choice on one
/// screen also counts on the others.
@Observable
final class DogChoice {
    var chosenDogID: PersistentIdentifier?

    /// The chosen dog, else the first of the dogs. The first dog also counts
    /// when the chosen dog is not in the list any more.
    func shownDog(in dogs: [Dog]) -> Dog? {
        dogs.first { $0.persistentModelID == chosenDogID } ?? dogs.first
    }
}
