//
//  StartWalkButton.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import SwiftData
import SwiftUI

/// What "Start Walk" does when the walker taps it.
enum StartWalkChoice: Equatable {
    /// Starts the walk with this dog, without the sheet that chooses the dogs.
    case startAtOnce(Dog)
    /// Opens the sheet that chooses the dogs, with these dogs already chosen.
    case chooseDogs(chosen: Set<PersistentIdentifier>)

    /// Retired dogs cannot join walks. When only one dog can join walks,
    /// the walk starts at once with that dog. If not, the sheet opens with
    /// the shown dog already chosen, unless it is a retired dog.
    static func onTap(dogs: [Dog], shownDog: Dog?) -> Self {
        let joining = dogs.filter { !$0.isRetired }
        if joining.count == 1 {
            return .startAtOnce(joining[0])
        }
        let chosen = joining.filter { $0 == shownDog }.map(\.persistentModelID)
        return .chooseDogs(chosen: Set(chosen))
    }
}

/// The full-width "Start Walk" button at the bottom of the home screen.
///
/// The home screen passes the dog that it shows, and the sheet that chooses
/// the dogs then opens with that dog already chosen.
struct StartWalkButton: View {
    let shownDog: Dog?
    @Environment(CurrentWalk.self) private var current
    @Query private var dogs: [Dog]
    @State private var isChoosingDogs = false
    @State private var chosen: Set<PersistentIdentifier> = []

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
