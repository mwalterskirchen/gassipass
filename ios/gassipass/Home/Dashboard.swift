//
//  Dashboard.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import GassiPassCore
import SwiftUI

/// The totals of the shown dog in the logbook of the home screen, side by
/// side: its total distance, and the numbers of areas and streets that it
/// has completed. They are small, because the game above them comes first.
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
        HStack(alignment: .top, spacing: 12) {
            Total(WalkFormat.distance(distanceMetres), label: "Total distance")
            Total(totals?.completedAreaCount.formatted(), placeholder: "00", label: "Areas completed")
            Total(totals?.completedStreetCount.formatted(), placeholder: "00", label: "Streets completed")
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

    init(_ value: String?, placeholder: String = "", label: LocalizedStringKey) {
        self.value = value
        self.placeholder = placeholder
        self.label = label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value ?? placeholder)
                .bigFigure(size: 26)
                .redacted(reason: value == nil ? .placeholder : [])
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
