//
//  HomeScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// The home screen: the pinned areas with their completion for one dog. An
/// area opens its area screen, where the user can unpin it.
///
/// The dog picker lists every dog, like the collection book.
struct HomeScreen: View {
    @Environment(Collections.self) private var collections
    @Query(sort: \Dog.name) private var dogs: [Dog]
    @Query private var pins: [PinnedArea]
    @State private var chosenDogID: PersistentIdentifier?

    var body: some View {
        NavigationStack {
            Group {
                if dogs.isEmpty {
                    ContentUnavailableView(
                        "No Dogs", systemImage: "pawprint",
                        description: Text("Add a dog to see its pinned areas."))
                } else if pins.isEmpty {
                    ContentUnavailableView(
                        "No Pinned Areas", systemImage: "pin",
                        description: Text("Pin an area on its screen in the collection book to show it here."))
                } else if collections.areas.isEmpty {
                    ProgressView()
                } else {
                    List(pages) { page in
                        NavigationLink(value: page.id) {
                            PageRow(page: page)
                        }
                    }
                }
            }
            .navigationTitle("Pinned Areas")
            .toolbar {
                if !dogs.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        DogPicker(dogs: dogs, shownDog: shownDog, chosenDogID: $chosenDogID)
                    }
                }
            }
            .navigationDestination(for: Area.ID.self) { areaID in
                if let area = collections.areas[areaID], let dog = shownDog {
                    AreaScreen(
                        page: CollectionBook.page(
                            of: area, collection: collections.collection(of: dog.persistentModelID),
                            dog: dog.persistentModelID, records: dog.completedAreaRecords),
                        streets: collections.streetEntries(of: areaID, for: dog),
                        dogName: dog.name)
                }
            }
        }
    }

    /// The dog whose pinned areas the screen shows: the chosen dog, else the first.
    private var shownDog: Dog? {
        dogs.first { $0.persistentModelID == chosenDogID } ?? dogs.first
    }

    private var pages: [CollectionBook.Page] {
        guard let dog = shownDog else { return [] }
        return CollectionBook.pinnedPages(
            pinned: pins.map(\.area), areas: Array(collections.areas.values),
            collection: collections.collection(of: dog.persistentModelID),
            dog: dog.persistentModelID, records: dog.completedAreaRecords)
    }
}

#Preview {
    HomeScreen()
        .environment(Collections())
        .modelContainer(for: [Dog.self, PinnedArea.self], inMemory: true)
}
