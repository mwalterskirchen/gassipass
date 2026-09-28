//
//  DogsScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// The list of dogs. The retired dogs have a section of their own. A dog
/// opens the sheet that edits it.
struct DogsScreen: View {
    @Query(sort: \Dog.name) private var dogs: [Dog]
    @State private var isAddingDog = false
    @State private var editedDog: Dog?

    var body: some View {
        NavigationStack {
            List {
                let joiningWalks = dogs.filter { !$0.isRetired }
                let retired = dogs.filter(\.isRetired)
                if !joiningWalks.isEmpty {
                    Section {
                        ForEach(joiningWalks, content: row)
                    }
                }
                if !retired.isEmpty {
                    Section("Retired Dogs") {
                        ForEach(retired, content: row)
                    }
                }
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
                DogSheet()
            }
            .sheet(item: $editedDog) { dog in
                DogSheet(dog: dog)
            }
        }
    }

    private func row(_ dog: Dog) -> some View {
        Button {
            editedDog = dog
        } label: {
            HStack(spacing: 14) {
                DogBadge(dog: dog)
                    .saturation(dog.isRetired ? 0 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dog.name)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Group {
                        if let retiredAt = dog.retiredAt {
                            Text("Retired on \(retiredAt.formatted(date: .abbreviated, time: .omitted))")
                        } else {
                            Text("^[\(dog.endedWalkCount) walk](inflect: true)")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Edits the dog")
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
