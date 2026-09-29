//
//  DogSheet.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import PhotosUI
import SwiftData
import SwiftUI

/// Adds a dog, or edits the name, the photo, the coat colour and the
/// retirement of a dog. Nothing here deletes a dog.
///
/// The coat colour shows only without a photo, because the badge then
/// shows it. A new dog starts with a coat colour that no other dog has.
struct DogSheet: View {
    /// The dog to edit, or nil to add a new dog.
    var dog: Dog?
    var onAdd: (Dog) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var dogs: [Dog]
    @State private var name: String
    @State private var photo: Data?
    @State private var photoItem: PhotosPickerItem?
    /// The chosen coat colour, or nil to keep the coat colour of the dog,
    /// or to give a new dog one that no other dog has.
    @State private var chosenCoat: CoatColour?
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
        // The label of the picker is a Sendable closure, so it gets copies.
        let badgeName = trimmedName.isEmpty ? "?" : trimmedName
        let badgePhoto = photo
        let badgeCoat = coat
        return VStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                DogBadge(name: badgeName, photo: badgePhoto, coat: badgeCoat, size: 96)
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
            if photo == nil {
                coatPicker
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A round swatch for each coat colour. The chosen one has a ring.
    private var coatPicker: some View {
        HStack(spacing: 12) {
            ForEach(CoatColour.allCases) { colour in
                Button {
                    chosenCoat = colour
                } label: {
                    Circle()
                        .fill(colour.color)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                        }
                        .padding(4)
                        .overlay {
                            if colour == coat {
                                Circle().strokeBorder(.primary, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(colour.name))
                .accessibilityAddTraits(colour == coat ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Coat colour")
    }

    private var coat: CoatColour {
        if let chosenCoat { return chosenCoat }
        if let dog { return dog.coatColour }
        return CoatColour.forNewDog(besides: dogs.filter { !$0.isRetired }.map(\.coatColour))
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
        saved.coatColour = coat
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
