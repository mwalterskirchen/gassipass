//
//  AddDogSheet.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// Adds a dog with a name.
struct AddDogSheet: View {
    var onAdd: (Dog) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(add)
            }
            .navigationTitle("New Dog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func add() {
        guard !trimmedName.isEmpty else { return }
        let dog = Dog(name: trimmedName)
        context.insert(dog)
        try? context.save()
        onAdd(dog)
        dismiss()
    }
}
