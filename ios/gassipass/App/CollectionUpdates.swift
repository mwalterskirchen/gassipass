//
//  CollectionUpdates.swift
//  gassipass
//

import GassiPassCore
import SwiftData
import SwiftUI

/// Updates the collections whenever the dogs, the ended walks, their dogs,
/// the completed records, the area steps, the ring stamps or the home base
/// change. The app starts the first update at launch.
struct CollectionUpdates: ViewModifier {
    @Environment(Collections.self) private var collections
    @Query(Dog.all()) private var dogs: [Dog]
    /// A walk counts when it has ended. During a walk, `CurrentWalk` matches its points.
    @Query(Walk.ended()) private var walks: [Walk]
    /// The update merges two records of the same dog and goal.
    @Query private var completedAreas: [CompletedArea]
    @Query private var completedStreets: [CompletedStreet]
    @Query private var areaSteps: [AreaStep]
    @Query private var completedRings: [CompletedRing]
    @Query(Pack.all()) private var packs: [Pack]

    func body(content: Content) -> some View {
        content
            .task(id: updateInput) {
                await collections.update()
            }
    }

    /// What an update depends on. A change starts a new update.
    private var updateInput: UpdateInput {
        UpdateInput(
            collections: CollectionInput(dogs: dogs, walks: walks),
            recordCount: completedAreas.count + completedStreets.count + areaSteps.count + completedRings.count,
            homeBase: packs.first?.homeBase)
    }
}

private struct UpdateInput: Equatable {
    let collections: CollectionInput
    let recordCount: Int
    let homeBase: HomeBase?
}
