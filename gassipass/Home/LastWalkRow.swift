//
//  LastWalkRow.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import SwiftData
import SwiftUI

/// The last walk of the shown dog on the home screen: the drawing of its
/// track, the number of segments that became collected during it, its day
/// and its distance. The row opens the walk's detail screen.
///
/// The segments are the first line, because they are what the walk gave
/// to the collection. The distance is the distance of the walk, not the
/// collected length.
struct LastWalkRow: View {
    enum Content {
        /// The count is not known yet, so the row shows a grey placeholder for it.
        case loading(Walk)
        /// The dog has no walks yet.
        case noWalks
        /// The last walk and the number of segments that the dog collected during it.
        case walk(Walk, collectedSegmentCount: Int)
    }

    let content: Content

    var body: some View {
        switch content {
        case .loading(let walk):
            row(walk: walk, collectedSegmentCount: nil)
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
                row(walk: walk, collectedSegmentCount: count)
            }
        }
    }

    /// The row of the walk. Without a count, the first line is a grey
    /// placeholder of the same size.
    private func row(walk: Walk, collectedSegmentCount: Int?) -> some View {
        HStack(spacing: 14) {
            TrackThumbnail(walk: walk)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(collectedSegmentCount ?? 100) segments collected")
                    .font(.figures(.headline))
                    .monospacedDigit()
                    .redacted(reason: collectedSegmentCount == nil ? .placeholder : [])
                HStack(spacing: 12) {
                    Text(WalkFormat.relativeDay(walk.startedAt))
                    Text(WalkFormat.distance(walk.distanceMetres))
                }
                .font(.figures(.subheadline, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let walk = Walk(startedAt: .now.addingTimeInterval(-86_400), dogs: [])
    walk.distanceMetres = 3200
    return NavigationStack {
        List {
            LastWalkRow(content: .walk(walk, collectedSegmentCount: 14))
            LastWalkRow(content: .loading(walk))
            LastWalkRow(content: .noWalks)
        }
    }
    .modelContainer(for: Walk.self, inMemory: true)
}
