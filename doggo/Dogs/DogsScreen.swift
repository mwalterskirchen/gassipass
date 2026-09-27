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
                Text(dog.name)
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
