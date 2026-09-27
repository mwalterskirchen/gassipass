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
                    Label(WalkFormat.duration(walk.duration), systemImage: "clock")
                    Spacer()
                    Label(WalkFormat.distance(walk.distanceMetres), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    Spacer()
                    Label(WalkFormat.dogs(walk), systemImage: "pawprint")
                }
                .font(.subheadline)
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle(walk.startedAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
    }
}
