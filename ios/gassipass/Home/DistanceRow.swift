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
            let gap: CGFloat = 1.5
            for (index, bar) in page.bars.enumerated() {
                let x = CGFloat(index) * slot + (slot - width) / 2
                let parts = bar.walkMetres.filter { $0 > 0 }
                if parts.isEmpty {
                    let stub = CGRect(x: x, y: size.height - 2, width: width, height: 2)
                    context.fill(Path(roundedRect: stub, cornerRadius: 1), with: .color(Color(.tertiaryLabel)))
                }
                var end = 0.0
                for (part, metres) in parts.enumerated() {
                    let lower = CGFloat(end / top) * size.height + (part > 0 ? gap / 2 : 0)
                    end += metres
                    let upper = CGFloat(end / top) * size.height - (part < parts.count - 1 ? gap / 2 : 0)
                    let rect = CGRect(x: x, y: size.height - max(upper, lower + 1.5), width: width, height: max(upper - lower, 1.5))
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
    let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)!.start
    let distance = DogDistance(walks: [0, 0, 1, 2, 2, 4].enumerated().map { index, day in
        let date = start.addingTimeInterval(Double(day) * 86_400 + Double(8 + index % 2 * 9) * 3600)
        return (id: UUID(), startedAt: date, endedAt: date.addingTimeInterval(3600), distanceMetres: Double(1500 + index * 700))
    })
    List {
        DistanceRow(distance: distance)
        DistanceRow(distance: DogDistance(walks: []))
    }
}
