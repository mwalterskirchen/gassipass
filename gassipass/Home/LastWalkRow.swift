//
//  LastWalkRow.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import SwiftData
import SwiftUI

/// The last walk of the shown dog below the totals on the home screen: its
/// day, its distance and the number of segments that became collected
/// during it, for example "Yesterday · 3.2 km · 14 segments collected". The
/// row opens the walk's detail screen.
///
/// The distance is the distance of the walk, not the collected length.
struct LastWalkRow: View {
    enum Content {
        /// The count is not known yet, so the row shows a grey placeholder.
        case loading
        /// The dog has no walks yet.
        case noWalks
        /// The last walk and the number of segments that the dog collected during it.
        case walk(Walk, collectedSegmentCount: Int)
    }

    let content: Content

    var body: some View {
        switch content {
        case .loading:
            line(Text(verbatim: "Yesterday · 0.0 km · 00 segments collected"), isPlaceholder: true)
        case .noWalks:
            VStack(alignment: .leading, spacing: 2) {
                Text("No walks yet")
                    .font(.headline)
                Text("Start a walk to collect the first segments.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .walk(let walk, let count):
            NavigationLink(value: walk) {
                line(Text("\(WalkFormat.relativeDay(walk.startedAt)) · \(WalkFormat.distance(walk.distanceMetres)) · \(count) segments collected"))
            }
        }
    }

    /// The line of the walk and its label. A placeholder line is grey.
    private func line(_ text: Text, isPlaceholder: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            text
                .font(.figures(.headline))
                .monospacedDigit()
                .redacted(reason: isPlaceholder ? .placeholder : [])
            Text("Last walk")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let walk = Walk(startedAt: .now.addingTimeInterval(-86_400), dogs: [])
    walk.distanceMetres = 3200
    return NavigationStack {
        List {
            LastWalkRow(content: .walk(walk, collectedSegmentCount: 14))
            LastWalkRow(content: .loading)
            LastWalkRow(content: .noWalks)
        }
    }
    .modelContainer(for: Walk.self, inMemory: true)
}
