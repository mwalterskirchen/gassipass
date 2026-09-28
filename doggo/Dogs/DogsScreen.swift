//
//  DogsScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// The list of dogs.
struct DogsScreen: View {
    @Query(sort: \Dog.name) private var dogs: [Dog]
    @State private var isAddingDog = false

    var body: some View {
        NavigationStack {
            List(dogs) { dog in
                HStack(spacing: 14) {
                    DogBadge(name: dog.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dog.name)
                            .font(.headline)
                        Text("^[\(dog.endedWalkCount) walk](inflect: true)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
            .overlay {
                if dogs.isEmpty {
                    ContentUnavailableView(
                        "No Dogs", systemImage: "pawprint",
                        description: Text("Add a dog to start collecting segments."))
                }
            }
            .navigationTitle("Dogs")
            .toolbar {
                Button("Add Dog", systemImage: "plus") { isAddingDog = true }
            }
            .sheet(isPresented: $isAddingDog) {
                AddDogSheet()
            }
        }
    }
}

private extension Dog {
    /// The number of walks of the dog that have ended. A walk that is still
    /// being recorded does not count.
    var endedWalkCount: Int {
        (walks ?? []).count { $0.endedAt != nil }
    }
}
