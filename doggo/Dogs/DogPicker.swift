//
//  DogPicker.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// A menu of the dogs, for a screen that shows the collection of one dog.
struct DogPicker: View {
    let dogs: [Dog]
    /// The dog that the screen shows.
    let shownDog: Dog?
    @Binding var chosenDogID: PersistentIdentifier?

    var body: some View {
        Picker("Dog", selection: Binding(get: { shownDog?.persistentModelID }, set: { chosenDogID = $0 })) {
            ForEach(dogs) { dog in
                Text(dog.name).tag(Optional(dog.persistentModelID))
            }
        }
        .pickerStyle(.menu)
    }
}
