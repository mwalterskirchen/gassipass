//
//  CollectionBookScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// The collection book: all areas of a canton for one dog, including areas
/// with no completion yet. Each area shows its completion, the date if the
/// dog has completed it, and a small map that the dog's collected segments
/// fill in. An area opens its area screen.
///
/// The dog picker lists every dog, so that the book of a retired dog stays
/// open (ticket 10 adds retired dogs).
struct CollectionBookScreen: View {
    @Environment(Collections.self) private var collections
    @Query(sort: \Dog.name) private var dogs: [Dog]
    @State private var chosenDogID: PersistentIdentifier?
    @State private var chosenCanton: String?

    var body: some View {
        NavigationStack {
            Group {
                if dogs.isEmpty {
                    ContentUnavailableView(
                        "No Dogs", systemImage: "pawprint",
                        description: Text("Add a dog to start its collection book."))
                } else if collections.areas.isEmpty {
                    ProgressView()
                } else {
                    book
                }
            }
            .navigationTitle("Collection Book")
            .toolbar {
                if !dogs.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        dogPicker
                    }
                }
            }
            .navigationDestination(for: Area.ID.self) { areaID in
                if let page = pages.first(where: { $0.id == areaID }) {
                    AreaScreen(page: page, dogName: shownDog?.name)
                }
            }
        }
    }

    private var book: some View {
        let pages = pages
        return List {
            Section {
                Picker("Canton", selection: Binding(get: { shownCanton }, set: { chosenCanton = $0 })) {
                    ForEach(cantons, id: \.self) { canton in
                        Text("Canton \(canton)").tag(Optional(canton))
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(pages) { page in
                    NavigationLink(value: page.id) {
                        PageRow(page: page)
                    }
                }
            } header: {
                Text("\(pages.count { $0.completedAt != nil }) of \(pages.count) completed")
            }
        }
    }

    private var dogPicker: some View {
        Picker("Dog", selection: Binding(get: { shownDog?.persistentModelID }, set: { chosenDogID = $0 })) {
            ForEach(dogs) { dog in
                Text(dog.name).tag(Optional(dog.persistentModelID))
            }
        }
        .pickerStyle(.menu)
    }

    /// The dog whose book the screen shows: the chosen dog, else the first.
    private var shownDog: Dog? {
        dogs.first { $0.persistentModelID == chosenDogID } ?? dogs.first
    }

    /// The cantons of the bundled map packages.
    private var cantons: [String] {
        Set(collections.areas.values.map(\.canton)).sorted()
    }

    /// The canton that the screen shows when the dog has collected nothing
    /// yet: canton Zürich, where the first test area Dietikon lies.
    private static let fallbackCanton = "ZH"

    /// The canton that the screen shows: the chosen canton, else the canton
    /// where the dog has collected the most segments, else the fallback.
    private var shownCanton: String? {
        if let chosenCanton { return chosenCanton }
        let collection = collections.collection(of: shownDog?.persistentModelID)
        let collectedByCanton = Dictionary(
            grouping: collection.collected.values.compactMap { collections.areas[$0.area]?.canton }, by: { $0 })
        guard !collectedByCanton.isEmpty else {
            return cantons.contains(Self.fallbackCanton) ? Self.fallbackCanton : cantons.first
        }
        return cantons.max { (collectedByCanton[$0]?.count ?? 0) < (collectedByCanton[$1]?.count ?? 0) }
    }

    private var pages: [CollectionBook.Page] {
        guard let shownCanton, let dog = shownDog else { return [] }
        return CollectionBook.pages(
            canton: shownCanton, areas: Array(collections.areas.values),
            collection: collections.collection(of: dog.persistentModelID),
            dog: dog.persistentModelID, records: dog.completedRecords)
    }
}

private struct PageRow: View {
    let page: CollectionBook.Page

    var body: some View {
        HStack(spacing: 12) {
            AreaMap(area: page.area.id, collectedSegments: page.collectedSegments)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.area.name)
                    .font(.headline)
                if let completedAt = page.completedAt {
                    Label(completedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color(SegmentMapView.collectedColor))
                } else {
                    Text("\(page.completion.collectedSegmentCount) of \(page.completion.segmentCount) segments")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            Spacer()
            Text(page.completion.formattedShare)
                .monospacedDigit()
        }
    }
}

#Preview {
    CollectionBookScreen()
        .environment(Collections())
}
