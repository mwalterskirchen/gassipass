//
//  StartWalkButton.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import GassiPassCore
import SwiftData
import SwiftUI

/// The full-width "Start Walk" button at the bottom of the home screen.
///
/// The home screen passes the dog that it shows, and the sheet that chooses
/// the dogs then opens with that dog already chosen.
struct StartWalkButton: View {
    let shownDog: Dog?
    @Environment(CurrentWalk.self) private var current
    @Query(Dog.all()) private var dogs: [Dog]
    @State private var isChoosingDogs = false
    @State private var chosen: Set<UUID> = []

    var body: some View {
        Button {
            switch StartWalkChoice.onTap(dogs: dogs, shownDog: shownDog) {
            case .startAtOnce(let dog):
                current.start(dogs: [dog])
            case .chooseDogs(let chosen):
                self.chosen = chosen
                isChoosingDogs = true
            }
        } label: {
            Label("Start Walk", systemImage: "figure.walk")
        }
        .buttonStyle(.forest)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .sheet(isPresented: $isChoosingDogs) {
            StartWalkSheet(chosen: chosen)
        }
    }
}

extension View {
    /// Puts the "Start Walk" button at the bottom of the screen.
    func startWalkButton(shownDog: Dog?) -> some View {
        safeAreaInset(edge: .bottom) {
            StartWalkButton(shownDog: shownDog)
        }
    }
}
