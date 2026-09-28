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
    @Environment(DogChoice.self) private var dogChoice
    @Query(sort: \Dog.name) private var dogs: [Dog]
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
                        DogPicker(dogs: dogs)
                    }
                }
            }
            .navigationDestination(for: Area.ID.self) { areaID in
                if let area = collections.areas[areaID] {
                    AreaScreen(area: area, dog: shownDog, collections: collections)
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

    private var shownDog: Dog? {
        dogChoice.shownDog(in: dogs)
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
        return collections.pages(canton: shownCanton, for: dog)
    }
}

#Preview {
    CollectionBookScreen()
        .environment(Collections())
        .environment(DogChoice())
}
