//
//  WalkStats.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreData
import SwiftUI

/// The duration, distance and dogs of a past walk, as labels for a stack.
struct WalkStats: View {
    /// Observed, so that the stats show the new dogs after a change.
    @ObservedObject var walk: Walk

    var body: some View {
        Label(WalkFormat.distance(walk.distanceMetres), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            .monospacedDigit()
        Label(WalkFormat.duration(walk.duration), systemImage: "clock")
            .monospacedDigit()
        Label(walk.dogNames, systemImage: "pawprint.fill")
            .lineLimit(1)
    }
}
