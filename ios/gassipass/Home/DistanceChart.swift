//
//  DistanceChart.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 15.10.2026.
//

import Charts
import SwiftUI

/// The bars of one page of the distance of a dog, in the colour of the
/// track, because the distance is the length of the track. In a page of
/// days, each walk of a day is its own piece of the bar, with a small gap
/// between the pieces, so that two walks on a day show as two pieces.
///
/// A tap on a bar selects it, and the other bars fade. A second tap on the
/// bar, or a tap beside the page, ends the selection. A tap and not a drag,
/// so that the screen still scrolls when the finger starts on the chart.
struct DistanceChart: View {
    let page: DistancePage
    /// The start of the selected bar.
    @Binding var selection: Date?

    var body: some View {
        let top = topKilometres
        Chart {
            ForEach(page.bars) { bar in
                ForEach(pieces(of: bar, top: top)) { piece in
                    BarMark(
                        x: .value("Date", bar.interval.start, unit: page.unit.barComponent),
                        yStart: .value("Distance", piece.lower),
                        yEnd: .value("Distance", piece.upper),
                        width: .ratio(0.6))
                    .cornerRadius(4)
                    .foregroundStyle(Color.track.opacity(isFaded(bar) ? 0.3 : 1))
                    // VoiceOver reads each bar once, with its whole distance.
                    .accessibilityHidden(!piece.isTop)
                    .accessibilityLabel(Text(DistanceFormat.barTitle(of: bar, unit: page.unit)))
                    .accessibilityValue(Text(WalkFormat.distance(bar.metres)))
                }
            }
        }
        .chartXScale(domain: page.interval.start...page.interval.end)
        .chartYScale(domain: 0...top)
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { tap in
                let tapped = proxy.value(atX: tap.location.x, as: Date.self).flatMap(page.bar(containing:))?.id
                selection = tapped == selectedBar?.id ? nil : tapped
            }
        }
        .chartXAxis { xAxis }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let kilometres = value.as(Double.self) {
                        Text(DistanceFormat.axisKilometres(kilometres))
                            .font(.figures(.caption, weight: .medium))
                    }
                }
            }
        }
        .frame(height: 200)
    }

    private var xAxis: some AxisContent {
        AxisMarks(values: xValues) { value in
            AxisValueLabel(centered: page.unit != .week) {
                if let date = value.as(Date.self) {
                    Text(xLabel(of: date))
                        .font(.figures(.caption, weight: .medium))
                }
            }
        }
    }

    /// The days of the week, every fourth week, or the months.
    private var xValues: AxisMarkValues {
        switch page.unit {
        case .day: .stride(by: .day)
        case .week: .stride(by: .weekOfYear, count: 4)
        case .month: .stride(by: .month)
        }
    }

    private func xLabel(of date: Date) -> String {
        switch page.unit {
        case .day: date.formatted(.dateTime.weekday(.abbreviated))
        case .week: date.formatted(.dateTime.day().month(.abbreviated))
        case .month: date.formatted(.dateTime.month(.narrow))
        }
    }

    /// The top of the chart, a little above the longest bar, and at least 1 km.
    private var topKilometres: Double {
        max((page.bars.map(\.metres).max() ?? 0) / 1000 * 1.1, 1)
    }

    private var selectedBar: DistanceBar? {
        selection.flatMap(page.bar(containing:))
    }

    private func isFaded(_ bar: DistanceBar) -> Bool {
        guard let selectedBar else { return false }
        return selectedBar.id != bar.id
    }

    /// A part of a bar, from its lower to its upper end in kilometres.
    private struct Piece: Identifiable {
        let id: Int
        let lower: Double
        let upper: Double
        /// Whether it is the top piece of its bar.
        let isTop: Bool
    }

    /// One piece for each walk in a page of days, otherwise one piece. A
    /// walk that counts nothing, because an earlier walk covers its time,
    /// gives no piece.
    private func pieces(of bar: DistanceBar, top: Double) -> [Piece] {
        let parts = (page.unit == .day ? bar.walkMetres : [bar.metres]).map { $0 / 1000 }.filter { $0 > 0 }
        let gap = top * 0.02
        var end = 0.0
        return parts.indices.map { index in
            let lower = end + (index > 0 ? gap / 2 : 0)
            end += parts[index]
            let upper = end - (index < parts.count - 1 ? gap / 2 : 0)
            // A very short walk still shows as a sliver.
            return Piece(id: index, lower: lower, upper: max(upper, lower + top * 0.01), isTop: index == parts.count - 1)
        }
    }
}

/// Formats the titles and numbers of the distance screen.
enum DistanceFormat {
    /// The kilometres of a line of the chart, for example "10 km".
    static func axisKilometres(_ kilometres: Double) -> String {
        Measurement(value: kilometres, unit: UnitLength.kilometers)
            .formatted(.measurement(
                width: .abbreviated, usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    /// The day, the week or the month of a bar, for example "Tuesday 13
    /// October", "12–18 Oct" or "October 2026".
    static func barTitle(of bar: DistanceBar, unit: DistanceUnit) -> String {
        switch unit {
        case .day: bar.interval.start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .week: days(of: bar.interval)
        case .month: bar.interval.start.formatted(.dateTime.month(.wide).year())
        }
    }

    /// The days of an interval, for example "12–18 Oct 2026". The last day
    /// is the day before the end of the interval.
    static func days(of interval: DateInterval) -> String {
        let lastDay = interval.end.addingTimeInterval(-1)
        return (interval.start..<max(lastDay, interval.start))
            .formatted(.interval.day().month(.abbreviated).year())
    }
}

#Preview {
    @Previewable @State var selection: Date?
    let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)!.start
    let distance = DogDistance(walks: [0, 0, 1, 2, 2, 4, 5].enumerated().map { index, day in
        let date = start.addingTimeInterval(Double(day) * 86_400 + Double(8 + index % 2 * 9) * 3600)
        return (id: UUID(), startedAt: date, endedAt: date.addingTimeInterval(3600), distanceMetres: Double(1500 + index * 700))
    })
    DistanceChart(page: distance.page(.day, containing: .now), selection: $selection)
        .padding()
}
