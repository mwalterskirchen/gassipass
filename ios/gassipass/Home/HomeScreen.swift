//
//  HomeScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import GassiPassCore
import SwiftData
import SwiftUI

/// The home screen of one dog. The game comes first: the card of the weekly
/// goals, the ring card, and the pinned areas with their completion. The
/// logbook comes last, because the distance earns no stamp: the totals, the
/// distance of this week and the last walk. The ring card opens the map
/// around the home base, an area opens its area screen, where the user can
/// unpin it, the distance of this week opens the distance screen, and the
/// last walk opens its detail screen. The title is the name of the dog.
///
/// The dog menu shows the badge of the dog, because the title is already
/// its name. It lists every dog, like the passport, and "Manage Dogs" pushes
/// the list of dogs. "Start Walk" chooses the shown dog in advance, unless
/// it is a retired dog. The gear button pushes the settings screen. It is
/// the last button, so that it stays in the corner.
struct HomeScreen: View {
    @Environment(Collections.self) private var collections
    @Environment(DogChoice.self) private var dogChoice
    @Query(Dog.all()) private var dogs: [Dog]
    @Query(PinnedArea.all()) private var pins: [PinnedArea]
    @Query(Walk.ended()) private var walks: [Walk]
    /// What "Manage Dogs" and a weekly goal push. The other screens come
    /// from their links.
    @State private var path = NavigationPath()
    @State private var isAddingDog = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let shownDog {
                    let distance = DogDistance(walks.filter { $0.hasDog(shownDog) })
                    List {
                        if shownDog.retiredAt == nil {
                            Section {
                                GoalCard(dog: shownDog) { place in
                                    switch place {
                                    case .street(let street): path.append(Route.street(street))
                                    case .area(let area): path.append(area)
                                    }
                                }
                            }
                        }
                        if let pack = shownDog.pack {
                            Section {
                                RingCard(pack: pack, dog: shownDog)
                            }
                        }
                        Section("Pinned Areas") {
                            pinnedAreas
                        }
                        Section("Logbook") {
                            Dashboard(distanceMetres: distance.totalMetres, totals: collections.totals(of: shownDog))
                                .padding(.vertical, 4)
                            NavigationLink {
                                DistanceScreen(dog: shownDog)
                            } label: {
                                DistanceRow(distance: distance)
                            }
                            LastWalkRow(content: lastWalk(of: shownDog))
                        }
                    }
                    .listSectionSpacing(.compact)
                    // Another dog is new content, not a change of the
                    // numbers, so its totals do not roll in.
                    .id(shownDog.id)
                } else {
                    // An empty list, so that a phone without dogs can pull
                    // to refresh, for example after a failed first download.
                    List {}
                        .overlay {
                            ContentUnavailableView {
                                Label("No Dogs", systemImage: "pawprint")
                            } description: {
                                Text("Add a dog to see the completion of the pinned areas.")
                            } actions: {
                                Button("Add Dog") { isAddingDog = true }
                                    .buttonStyle(.glassProminent)
                            }
                        }
                }
            }
            .refreshesPack()
            .navigationTitle(shownDog?.name ?? String(localized: "Home"))
            .startWalkButton(shownDog: shownDog)
            .toolbar {
                if !dogs.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Only the badge, because the title is already the name.
                        DogPicker(dogs: dogs, label: .badge) { path.append(Route.dogs) }
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
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .dogs:
                    DogsScreen()
                case .street(let street):
                    MapScreen(street: street)
                        .navigationTitle(street.name)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(isPresented: $isAddingDog) {
                DogSheet()
            }
        }
    }

    /// A screen that the home screen pushes without a link.
    private enum Route: Hashable {
        case dogs
        /// The map on the street of a weekly goal.
        case street(Street.ID)
    }

    @ViewBuilder private var pinnedAreas: some View {
        if pins.isEmpty {
            Text("Pin an area on its screen in the passport to show it here.")
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

    private var pages: [Passport.Page] {
        guard let dog = shownDog else { return [] }
        return collections.pinnedPages(pins.map(\.area), for: dog)
    }
}

#Preview {
    HomeScreen()
        .environment(Collections.preview())
        .environment(DogChoice())
        .environment(CurrentWalk.preview())
        .environment(Packs.preview)
        .environment(Account.preview)
        .environment(AppSettings())
        .modelContainer(.preview)
}
