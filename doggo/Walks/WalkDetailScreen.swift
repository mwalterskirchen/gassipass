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
    }
}
