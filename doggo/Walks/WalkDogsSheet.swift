//
//  WalkDogsSheet.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import SwiftData
import SwiftUI

/// Adds or removes dogs for the whole of an ended walk. A walk has at least
/// one dog, so the last dog cannot be removed. Retired dogs appear too,
/// because they can have taken part in the walk. The collections change to
/// match when `CollectionUpdates` sees the new dogs.
struct WalkDogsSheet: View {
    let walk: Walk

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Dog.name) private var dogs: [Dog]
    @State private var chosen: Set<PersistentIdentifier>

    init(walk: Walk) {
        self.walk = walk
        _chosen = State(initialValue: Set((walk.dogs ?? []).map(\.persistentModelID)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DogCheckRows(dogs: dogs, chosen: $chosen)
                } header: {
                    Text("Who was walking?")
                } footer: {
                    Text("Each dog collects the segments of the whole walk.")
                }
            }
            .navigationTitle("Dogs of the Walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        walk.dogs = dogs.filter { chosen.contains($0.persistentModelID) }
                        try? context.save()
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
