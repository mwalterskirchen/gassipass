//
//  TrackThumbnail.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import SwiftUI

/// A small drawing of the track of a past walk, in the colour of the track
/// on the map, so that the walks in the list look different.
///
/// The track decodes off the main thread, and the drawing is kept for each
/// walk, because the track of an ended walk does not change.
///
/// A kept drawing is the first state of the view. A state that the task
/// sets before its first await does not redraw the canvas.
struct TrackThumbnail: View {
    let walk: Walk
    @State private var outline: [CGPoint]

    /// The outline of each walk that the list has drawn.
    private static var outlines: [UUID: [CGPoint]] = [:]

    init(walk: Walk) {
        self.walk = walk
        _outline = State(initialValue: Self.outlines[walk.id] ?? [])
    }

    var body: some View {
        Canvas { context, size in
            guard outline.count > 1 else { return }
            var path = Path()
            path.addLines(outline.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
            context.stroke(path, with: .color(.track),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .padding(7)
        .frame(width: 52, height: 52)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
        .task(id: walk.id) {
            let id = walk.id
            if let kept = Self.outlines[id] {
                // On the first appearance the kept drawing is the state
                // already. This is for a row that shows another walk now.
                if outline != kept {
                    outline = kept
                }
                return
            }
            let drawn = await Self.outline(of: walk.trackData)
            Self.outlines[id] = drawn
            outline = drawn
        }
        .accessibilityHidden(true)
    }

    /// The filtered points of the track, at most about 120 of them, placed in
    /// a square from 0 to 1 without distortion.
    @concurrent nonisolated private static func outline(of data: Data?) async -> [CGPoint] {
        guard let data, let track = try? Track(data: data) else { return [] }
        let points = track.filteredPoints
        guard points.count > 1 else { return [] }
        let step = max(points.count / 120, 1)
        let kept = stride(from: 0, to: points.count, by: step).map { points[$0] } + [points[points.count - 1]]
        let coordinates = kept.map(\.coordinate)
        let project = AreaMapRenderer.projection(of: coordinates, into: CGRect(x: 0, y: 0, width: 1, height: 1))
        return coordinates.map(project)
    }
}
