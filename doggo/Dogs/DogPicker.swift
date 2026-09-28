//
//  DogPicker.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// A menu of the dogs that sets the dog choice of the app.
struct DogPicker: View {
    let dogs: [Dog]
    @Environment(DogChoice.self) private var choice

    var body: some View {
        Picker("Dog", selection: Binding(
            get: { choice.shownDog(in: dogs)?.persistentModelID }, set: { choice.chosenDogID = $0 })
        ) {
            ForEach(dogs) { dog in
                Text(dog.name).tag(Optional(dog.persistentModelID))
            }
        }
        .pickerStyle(.menu)
    }
}
