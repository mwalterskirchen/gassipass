//
//  StartWalkSheet.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// Chooses the dogs that take part and starts the walk. A walk has at least
/// one dog, so the walk cannot start before the walker chooses one.
struct StartWalkSheet: View {
    @Environment(WalkRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Dog.name) private var dogs: [Dog]
    @State private var chosen: Set<PersistentIdentifier> = []
    @State private var isAddingDog = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(dogs) { dog in
                        Button {
                            if chosen.contains(dog.persistentModelID) {
                                chosen.remove(dog.persistentModelID)
                            } else {
                                chosen.insert(dog.persistentModelID)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                DogBadge(name: dog.name, size: 34)
                                Text(dog.name)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                Image(systemName: chosen.contains(dog.persistentModelID)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(chosen.contains(dog.persistentModelID)
                                                     ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .accessibilityAddTraits(chosen.contains(dog.persistentModelID) ? .isSelected : [])
                        }
                    }
                    Button("Add Dog", systemImage: "plus") { isAddingDog = true }
                } header: {
                    Text("Who is walking?")
                } footer: {
                    if dogs.isEmpty {
                        Text("Add a dog before you start a walk.")
                    }
                }
            }
            .navigationTitle("Start Walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        recorder.start(dogs: dogs.filter { chosen.contains($0.persistentModelID) })
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
            .sheet(isPresented: $isAddingDog) {
                AddDogSheet { chosen.insert($0.persistentModelID) }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
