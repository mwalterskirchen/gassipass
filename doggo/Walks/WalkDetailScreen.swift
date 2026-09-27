//
//  WalkDetailScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// Shows one past walk and its track on the map.
struct WalkDetailScreen: View {
    let walk: Walk

    var body: some View {
        MapScreen(track: walk.track)
            .safeAreaInset(edge: .top) {
                HStack {
                    WalkStats(walk: walk)
                }
                .font(.subheadline)
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle(WalkFormat.date(walk.startedAt))
            .navigationBarTitleDisplayMode(.inline)
    }
}
