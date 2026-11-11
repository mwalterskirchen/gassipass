//
//  MapLegend.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 11.11.2026.
//

import SwiftUI

/// A short line in the style of the map before the title: solid apricot for
/// collected segments, dashed green for segments that are not collected.
struct MapLegendLabelStyle: LabelStyle {
    let isCollected: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Canvas { context, size in
                var line = Path()
                line.move(to: CGPoint(x: 2, y: size.height / 2))
                line.addLine(to: CGPoint(x: size.width - 2, y: size.height / 2))
                if isCollected {
                    context.stroke(line, with: .color(.collectedEdge),
                                   style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    context.stroke(line, with: .color(.collected),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round))
                } else {
                    context.stroke(line, with: .color(.notCollected),
                                   style: StrokeStyle(lineWidth: 2.5, dash: [5, 3.5]))
                }
            }
            .frame(width: 20, height: 8)
            configuration.title
                .foregroundStyle(.primary)
        }
    }
}

extension View {
    /// The glass capsule of a legend or a caption on a map.
    func legendCapsule() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(in: .capsule)
    }

    /// Shows the attributions of the map data at the bottom of a map.
    func mapAttribution() -> some View {
        overlay(alignment: .bottom) {
            MapAttribution()
                .padding(.horizontal)
                .padding(.bottom, 4)
        }
    }
}
