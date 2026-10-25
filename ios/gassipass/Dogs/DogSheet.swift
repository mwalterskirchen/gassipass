//
//  DogSheet.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import PhotosUI
import SwiftData
import SwiftUI

/// Adds a dog, or edits the name, the photo, the date of birth and the
/// retirement of a dog. Nothing here deletes a dog.
struct DogSheet: View {
    /// The dog to edit, or nil to add a new dog.
    var dog: Dog?
    var onAdd: (Dog) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(Packs.self) private var packs
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var photo: Data?
    @State private var photoItem: PhotosPickerItem?
    /// The date of birth, or nil if the members do not know it.
    @State private var bornOn: Date?
    @State private var isRetired: Bool
    @State private var retiredAt: Date
    @State private var retirementReason: String

    init(dog: Dog? = nil, onAdd: @escaping (Dog) -> Void = { _ in }) {
        self.dog = dog
        self.onAdd = onAdd
        _name = State(initialValue: dog?.name ?? "")
        _photo = State(initialValue: dog?.photoData)
        _bornOn = State(initialValue: dog?.bornOn)
        _isRetired = State(initialValue: dog?.isRetired ?? false)
        _retiredAt = State(initialValue: dog?.retiredAt ?? .now)
        _retirementReason = State(initialValue: dog?.retirementReason ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The date of birth as the midnight in Zurich at the start of the day,
    /// as the server keeps it.
    private var storedBornOn: Date? {
        bornOn.map(WeekCalendar.calendar.startOfDay(for:))
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
                birth
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
        return VStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                DogBadge(name: badgeName, photo: badgePhoto, size: 96)
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

    private var birth: some View {
        Section {
            if let bornOn {
                DatePicker(
                    "Date of Birth",
                    selection: Binding(get: { bornOn }, set: { self.bornOn = $0 }),
                    in: ...Date.now, displayedComponents: .date)
                // The server keeps the day in Zurich.
                .environment(\.timeZone, WeekCalendar.calendar.timeZone)
                Button("Remove Date of Birth", role: .destructive) {
                    withAnimation { self.bornOn = nil }
                }
            } else {
                Button("Add Date of Birth") {
                    withAnimation { bornOn = WeekCalendar.calendar.startOfDay(for: .now) }
                }
            }
        } footer: {
            Text("The passport shows the age of the dog. You can leave the date of birth empty.")
        }
    }

    private var retirement: some View {
        Section {
            Toggle("Retired", isOn: $isRetired.animation())
            if isRetired {
                DatePicker("Since", selection: $retiredAt, in: ...Date.now, displayedComponents: .date)
                TextField("Reason (optional)", text: $retirementReason, axis: .vertical)
            }
        } footer: {
            Text("A retired dog no longer joins walks. Its collection, completions and passport stay.")
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let dog {
            dog.name = trimmedName
            dog.photoData = photo
            dog.bornOn = storedBornOn
            if isRetired {
                dog.retire(
                    on: retiredAt,
                    reason: retirementReason.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                dog.unretire()
            }
            dog.noteChange()
            try? context.save()
        } else if let added = try? packs.addDog(named: trimmedName, photoData: photo, bornOn: storedBornOn) {
            onAdd(added)
        }
        dismiss()
    }
}
