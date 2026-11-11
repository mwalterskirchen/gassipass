//
//  DogPicker.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import GassiPassCore
import SwiftUI

/// A menu of the dogs that sets the dog choice of the app. Its label is the
/// badge of the shown dog on every screen, so that the user finds the same
/// control in the same corner. A screen without "Manage Dogs" shows it only
/// when there is more than one dog, because the only dog is always the
/// shown dog.
struct DogPicker: View {
    let dogs: [Dog]
    /// Opens the list of dogs. With it, the menu ends with "Manage Dogs",
    /// so that the badge is the place for everything about the dogs.
    var manage: (() -> Void)?
    @Environment(DogChoice.self) private var choice

    var body: some View {
        Menu {
            if dogs.count > 1 {
                picker
            }
            if let manage {
                Button("Manage Dogs", systemImage: "pawprint", action: manage)
            }
        } label: {
            if let shownDog {
                DogBadge(dog: shownDog, size: 30)
            }
        }
        .accessibilityLabel(Text("Dog"))
        .accessibilityValue(Text(shownDog?.name ?? ""))
    }

    private var picker: some View {
        Picker("Dog", selection: Binding(
            get: { shownDog?.id }, set: { choice.choose($0) })
        ) {
            ForEach(dogs) { dog in
                Text(dog.name).tag(Optional(dog.id))
            }
        }
    }

    private var shownDog: Dog? {
        choice.shownDog(in: dogs)
    }
}
