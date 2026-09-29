//
//  StartWalkSheet.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// Chooses the dogs that take part and starts the walk. A walk has at least
/// one dog, so the walk cannot start before the walker chooses one. A
/// retired dog does not appear.
struct StartWalkSheet: View {
    @Environment(CurrentWalk.self) private var current
    @Environment(\.dismiss) private var dismiss
    @Query(filter: Dog.canJoinWalks, sort: \Dog.name) private var dogs: [Dog]
    @State private var chosen: Set<PersistentIdentifier> = []
    @State private var isAddingDog = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DogCheckRows(dogs: dogs, chosen: $chosen)
                    Button("Add Dog", systemImage: "plus") { isAddingDog = true }
                } header: {
                    Text("Who is walking?")
                } footer: {
                    if dogs.isEmpty {
                        Text("Add a dog before you start a walk.")
                    }
                }
            }
            // A key of its own, because a sheet title has less room than the button.
            .navigationTitle(String(localized: "StartWalkSheet.title", defaultValue: "Start Walk"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        current.start(dogs: dogs.filter { chosen.contains($0.persistentModelID) })
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
            .sheet(isPresented: $isAddingDog) {
                DogSheet { chosen.insert($0.persistentModelID) }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
