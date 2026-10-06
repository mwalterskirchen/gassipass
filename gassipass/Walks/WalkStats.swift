//
//  WalkStats.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreData
import SwiftUI

/// The duration, distance and dogs of a past walk, and the member who
/// recorded it, as labels for a stack.
struct WalkStats: View {
    /// Observed, so that the stats show the new dogs after a change.
    @ObservedObject var walk: Walk

    @Environment(Packs.self) private var packs

    var body: some View {
        Label(WalkFormat.distance(walk.distanceMetres), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            .monospacedDigit()
        Label(WalkFormat.duration(walk.duration), systemImage: "clock")
            .monospacedDigit()
        Label(walk.dogNames, systemImage: "pawprint.fill")
            .lineLimit(1)
        if let memberName = packs.shownMemberName(of: walk) {
            Label(memberName, systemImage: "person.fill")
                .lineLimit(1)
                .accessibilityLabel(Text("Recorded by \(memberName)"))
        }
    }
}
