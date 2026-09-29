//
//  DogSheet.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import PhotosUI
import SwiftData
import SwiftUI

/// Adds a dog, or edits the name, the photo and the retirement of a dog.
/// Nothing here deletes a dog.
struct DogSheet: View {
    /// The dog to edit, or nil to add a new dog.
    var dog: Dog?
    var onAdd: (Dog) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var photo: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var isRetired: Bool
    @State private var retiredAt: Date
    @State private var retirementReason: String

    init(dog: Dog? = nil, onAdd: @escaping (Dog) -> Void = { _ in }) {
        self.dog = dog
        self.onAdd = onAdd
        _name = State(initialValue: dog?.name ?? "")
        _photo = State(initialValue: dog?.photoData)
        _isRetired = State(initialValue: dog?.isRetired ?? false)
        _retiredAt = State(initialValue: dog?.retiredAt ?? .now)
        _retirementReason = State(initialValue: dog?.retirementReason ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    photoPicker
                }
                .listRowBackground(Color.clear)
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(save)
                }
                if dog != nil {
                    retirement
                }
            }
            .navigationTitle(dog == nil ? "New Dog" : "Edit Dog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(dog == nil ? "Add" : "Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .task(id: photoItem) {
                guard let photoItem, let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
                let stored = await Task.detached(priority: .userInitiated) { DogPhoto.storedData(from: data) }.value
                if let stored {
                    photo = stored
                }
            }
        }
    }

    private var photoPicker: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                DogBadge(name: trimmedName.isEmpty ? "?" : trimmedName, photo: photo, size: 96)
            }
            .accessibilityLabel(photo == nil ? "Choose Photo" : "Change Photo")
            HStack(spacing: 20) {
                PhotosPicker(photo == nil ? "Choose Photo" : "Change Photo", selection: $photoItem, matching: .images)
                if photo != nil {
                    Button("Remove Photo", role: .destructive) {
                        photo = nil
                        photoItem = nil
                    }
                }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
    }

    private var retirement: some View {
        Section {
            Toggle("Retired", isOn: $isRetired.animation())
            if isRetired {
                DatePicker("Since", selection: $retiredAt, in: ...Date.now, displayedComponents: .date)
                TextField("Reason (optional)", text: $retirementReason, axis: .vertical)
            }
        } footer: {
            Text("A retired dog no longer joins walks. Its collection, completions and collection book stay.")
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        let saved = dog ?? Dog(name: trimmedName)
        saved.name = trimmedName
        saved.photoData = photo
        if dog != nil {
            if isRetired {
                saved.retire(
                    on: retiredAt,
                    reason: retirementReason.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                saved.unretire()
            }
        } else {
            context.insert(saved)
        }
        try? context.save()
        if dog == nil {
            onAdd(saved)
        }
        dismiss()
    }
}
