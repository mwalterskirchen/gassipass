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
    @Environment(DogChoice.self) private var dogChoice
    @Query(sort: \Dog.name) private var dogs: [Dog]
    @Query private var pins: [PinnedArea]

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
                            PageRow(page: page, isProminent: true)
                        }
                    }
                }
            }
            .navigationTitle("Pinned Areas")
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

    private var shownDog: Dog? {
        dogChoice.shownDog(in: dogs)
    }

    private var pages: [CollectionBook.Page] {
        guard let dog = shownDog else { return [] }
        return collections.pinnedPages(pins.map(\.area), for: dog)
    }
}

#Preview {
    HomeScreen()
        .environment(Collections())
        .environment(DogChoice())
        .modelContainer(for: [Dog.self, PinnedArea.self], inMemory: true)
}
