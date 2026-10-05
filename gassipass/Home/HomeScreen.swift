//
//  HomeScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreData
import SwiftUI

/// The home screen: the dashboard with the totals and the last walk of one
/// dog, and the pinned areas with their completion for that dog. An area
/// opens its area screen, where the user can unpin it, and the last walk
/// opens its detail screen. The title is the name of the dog.
///
/// The dog picker shows the badge of the dog, because the title is already
/// its name. It lists every dog, like the collection book. "Start Walk"
/// chooses the shown dog in advance, unless it is a retired dog. The gear
/// button pushes the settings screen. It is the last button, so that it
/// stays in the corner when the dog picker appears.
struct HomeScreen: View {
    @Environment(Collections.self) private var collections
    @Environment(DogChoice.self) private var dogChoice
    @FetchRequest(fetchRequest: Dog.all()) private var dogs
    @FetchRequest(fetchRequest: PinnedArea.all()) private var pins
    @FetchRequest(fetchRequest: Walk.ended()) private var walks

    var body: some View {
        NavigationStack {
            Group {
                if let shownDog {
                    List {
                        Section {
                            Dashboard(totals: collections.totals(of: shownDog))
                                .padding(.vertical, 8)
                        }
                        Section("Last Walk") {
                            LastWalkRow(content: lastWalk(of: shownDog))
                        }
                        Section("Pinned Areas") {
                            pinnedAreas
                        }
                    }
                    // Another dog is new content, not a change of the
                    // numbers, so its totals do not roll in.
                    .id(shownDog.objectID)
                } else {
                    ContentUnavailableView(
                        "No Dogs", systemImage: "pawprint",
                        description: Text("Add a dog to see the completion of the pinned areas."))
                }
            }
            .navigationTitle(shownDog?.name ?? String(localized: "Home"))
            .startWalkButton(shownDog: shownDog)
            .toolbar {
                if dogs.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Only the badge, because the title is already the name.
                        DogPicker(dogs: Array(dogs), label: .badge)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsScreen()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationDestination(for: Area.ID.self) { areaID in
                if let area = collections.areas[areaID] {
                    AreaScreen(area: area, dog: shownDog, collections: collections)
                }
            }
            .navigationDestination(for: Walk.self) { walk in
                WalkDetailScreen(walk: walk)
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

    /// The newest ended walk that the dog takes part in, with the number
    /// of segments that the dog collected during it.
    private func lastWalk(of dog: Dog) -> LastWalkRow.Content {
        guard let walk = walks.first(where: { $0.hasDog(dog) }) else { return .noWalks }
        guard let count = collections.collectedSegmentCount(during: walk, of: dog) else { return .loading(walk) }
        return .walk(walk, collectedSegmentCount: count)
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
        .environment(AppSettings())
        .environment(\.managedObjectContext, .preview)
}
