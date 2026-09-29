//
//  HomeScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// The home screen: the dashboard with the totals of one dog, and the pinned
/// areas with their completion for that dog. An area opens its area screen,
/// where the user can unpin it. The title is the name of the dog.
///
/// The dog picker lists every dog, like the collection book. "Start Walk"
/// chooses the shown dog in advance, unless it is a retired dog.
struct HomeScreen: View {
    @Environment(Collections.self) private var collections
    @Environment(DogChoice.self) private var dogChoice
    @Query(sort: \Dog.name) private var dogs: [Dog]
    @Query private var pins: [PinnedArea]

    var body: some View {
        NavigationStack {
            Group {
                if let shownDog {
                    List {
                        Section {
                            Dashboard(totals: collections.totals(of: shownDog))
                                .padding(.vertical, 8)
                        }
                        Section("Pinned Areas") {
                            pinnedAreas
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Dogs", systemImage: "pawprint",
                        description: Text("Add a dog to see its pinned areas."))
                }
            }
            .navigationTitle(shownDog?.name ?? String(localized: "Home"))
            .startWalkButton(shownDog: shownDog)
            .toolbar {
                if dogs.count > 1 {
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

    @ViewBuilder private var pinnedAreas: some View {
        if pins.isEmpty {
            Text("Pin an area on its screen in the collection book to show it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if collections.areas.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            ForEach(pages) { page in
                NavigationLink(value: page.id) {
                    PageRow(page: page, isProminent: true)
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
        .environment(Collections.preview())
        .environment(DogChoice())
        .environment(CurrentWalk.preview())
        .modelContainer(for: [Dog.self, PinnedArea.self], inMemory: true)
}
