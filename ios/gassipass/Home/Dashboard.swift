//
//  Dashboard.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import SwiftUI

/// The totals of the shown dog at the top of the home screen: its total
/// distance, and the numbers of areas and streets that it has completed.
/// The totals do not respond to taps.
///
/// The distance shows at once, because it comes from the walks. Until the
/// collection has loaded, the completed numbers show grey placeholders of
/// the same size, so that the layout does not jump.
///
/// When the totals change later, for example after a walk, the digits roll
/// to their new values. The first totals appear without a roll, so that the
/// screen does not count up at every launch.
struct Dashboard: View {
    /// The total distance of the dog.
    let distanceMetres: Double
    /// The completed numbers, or nil until the collection has loaded.
    let totals: DogTotals?
    /// Whether totals have shown already, so that a change can animate.
    @State private var hasShownTotals = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Total(WalkFormat.distance(distanceMetres), label: "Total distance", size: 48)
            HStack(alignment: .top) {
                Total(totals?.completedAreaCount.formatted(), placeholder: "00", label: "Areas completed", size: 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Total(totals?.completedStreetCount.formatted(), placeholder: "00", label: "Streets completed", size: 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animatesChange(of: hasShownTotals ? totals : nil)
        .animatesChange(of: distanceMetres)
        .onChange(of: totals != nil, initial: true) { _, hasTotals in
            hasShownTotals = hasTotals
        }
    }
}

/// One total: a big number and its label. Without a value, the number is a
/// grey placeholder.
private struct Total: View {
    let value: String?
    let placeholder: String
    let label: LocalizedStringKey
    let size: CGFloat

    init(_ value: String?, placeholder: String = "", label: LocalizedStringKey, size: CGFloat) {
        self.value = value
        self.placeholder = placeholder
        self.label = label
        self.size = size
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value ?? placeholder)
                .monospacedDigit()
                .bigFiguresFont(size: size)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .redacted(reason: value == nil ? .placeholder : [])
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        Section {
            Dashboard(distanceMetres: 217_400, totals: DogTotals(completedAreaCount: 1, completedStreetCount: 14))
        }
        Section {
            Dashboard(distanceMetres: 0, totals: nil)
        }
    }
}
