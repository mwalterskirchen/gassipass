//
//  WalkDetailScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreData
import SwiftUI

/// Shows one past walk on the map: its track, and the segments that it
/// collected for at least one of its dogs. The walker can change the dogs
/// of the walk here, when there is more than one dog.
struct WalkDetailScreen: View {
    let walk: Walk

    @Environment(Collections.self) private var collections
    @FetchRequest(fetchRequest: Dog.all()) private var dogs
    @State private var isChangingDogs = false

    var body: some View {
        let collected = collections.collectedFeatures(during: walk)
        MapScreen(track: walk.track, collectedOnWalk: collected)
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        WalkStats(walk: walk)
                    }
                    .font(.figures(.subheadline, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(in: .capsule)
                    if !collected.isEmpty {
                        Label("Collected on this walk", systemImage: "circle.fill")
                            .labelStyle(MapLegendLabelStyle(isCollected: true))
                            .font(.footnote)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassEffect(in: .capsule)
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle(WalkFormat.date(walk.startedAt))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A walk has at least one dog, so with only one dog there is nothing to change.
                if dogs.count > 1 {
                    Button("Change Dogs", systemImage: "pawprint") { isChangingDogs = true }
                }
            }
            .sheet(isPresented: $isChangingDogs) {
                WalkDogsSheet(walk: walk)
            }
    }
}
