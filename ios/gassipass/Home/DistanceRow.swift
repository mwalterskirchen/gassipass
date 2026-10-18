//
//  DistanceRow.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 15.10.2026.
//

import SwiftUI

/// The distance of the shown dog in the current week, on the home screen:
/// the bars of the week, the distance of the week and the number of walks.
/// The dashboard above shows the total distance. The row opens the distance
/// screen.
struct DistanceRow: View {
    let distance: DogDistance

    var body: some View {
        let week = distance.page(.day, containing: .now)
        HStack(spacing: 14) {
            WeekBars(page: week)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(WalkFormat.distance(week.metres)) this week")
                    .font(.figures(.headline))
                Text(week.walkCount == 0 ? String(localized: "No walks") : String(localized: "\(week.walkCount) walks"))
                    .font(.figures(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A small drawing of the days of a week, in the same tile as the drawing
/// of a track. Each walk is a piece of the bar of its day, like in the
/// chart of the distance screen. A day without walks is a short stub.
private struct WeekBars: View {
    let page: DistancePage

    var body: some View {
        Canvas { context, size in
            let top = max(page.bars.map(\.metres).max() ?? 0, 1000)
            let slot = size.width / CGFloat(max(page.bars.count, 1))
            let width = (slot * 0.6).rounded()
            for (index, bar) in page.bars.enumerated() {
                let x = CGFloat(index) * slot + (slot - width) / 2
                let heights = bar.walkMetres.map { $0 / top * size.height }
                let pieces = StackedBar.pieces(of: heights, gap: 1.5, minimum: 1.5)
                if pieces.isEmpty {
                    let stub = CGRect(x: x, y: size.height - 2, width: width, height: 2)
                    context.fill(Path(roundedRect: stub, cornerRadius: 1), with: .color(Color(.tertiaryLabel)))
                }
                for piece in pieces {
                    let rect = CGRect(
                        x: x, y: size.height - piece.upperBound, width: width, height: piece.upperBound - piece.lowerBound)
                    context.fill(Path(roundedRect: rect, cornerRadius: min(width / 2, 1.5)), with: .color(.track))
                }
            }
        }
        .padding(8)
        .frame(width: 52, height: 52)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

#Preview {
    let start = WeekCalendar.week(containing: .now).start
    let distance = DogDistance(walks: [0, 0, 1, 2, 2, 4].enumerated().map { index, day in
        let date = start.addingTimeInterval(Double(day) * 86_400 + Double(8 + index % 2 * 9) * 3600)
        return (id: UUID(), startedAt: date, endedAt: date.addingTimeInterval(3600), distanceMetres: Double(1500 + index * 700))
    })
    List {
        DistanceRow(distance: distance)
        DistanceRow(distance: DogDistance(walks: []))
    }
}
