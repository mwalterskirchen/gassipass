//
//  WalkStats.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// The duration, distance and dogs of a past walk, as labels for a stack.
struct WalkStats: View {
    let walk: Walk

    var body: some View {
        Label(WalkFormat.duration(walk.duration), systemImage: "clock")
        Label(WalkFormat.distance(walk.distanceMetres), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        Label(walk.dogNames, systemImage: "pawprint")
            .lineLimit(1)
    }
}
