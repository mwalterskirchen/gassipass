//
//  DogPicker.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// A menu of the dogs that sets the dog choice of the app. The screens show
/// it only when there is more than one dog, because the only dog is always
/// the shown dog.
///
/// The menu shows the name of the shown dog, or only its badge on a screen
/// whose title is already the name of the dog.
struct DogPicker: View {
    enum Label {
        /// The name of the shown dog, with the arrows of a menu.
        case name
        /// The photo of the shown dog, else the first letter of its name.
        case badge
    }

    let dogs: [Dog]
    var label: Label = .name
    @Environment(DogChoice.self) private var choice

    var body: some View {
        switch label {
        case .name:
            picker
                .pickerStyle(.menu)
        case .badge:
            Menu {
                picker
            } label: {
                if let shownDog {
                    DogBadge(dog: shownDog, size: 30)
                }
            }
            .accessibilityLabel(Text("Dog"))
            .accessibilityValue(Text(shownDog?.name ?? ""))
        }
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
