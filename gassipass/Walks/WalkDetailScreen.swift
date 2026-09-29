//
//  WalkDetailScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// Shows one past walk and its track on the map. The walker can change the
/// dogs of the walk here, when there is more than one dog.
struct WalkDetailScreen: View {
    let walk: Walk

    @Query private var dogs: [Dog]
    @State private var isChangingDogs = false

    var body: some View {
        MapScreen(track: walk.track)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 16) {
                    WalkStats(walk: walk)
                }
                .font(.figures(.subheadline, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(in: .capsule)
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
