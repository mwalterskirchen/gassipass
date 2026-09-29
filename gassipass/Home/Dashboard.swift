//
//  Dashboard.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import SwiftUI

/// The totals of the shown dog at the top of the home screen: its collected
/// length, and the numbers of areas and streets that it has completed. The
/// totals do not respond to taps.
///
/// Until the collection has loaded, the numbers show grey placeholders of
/// the same size, so that the layout does not jump.
struct Dashboard: View {
    /// The totals, or nil until the collection has loaded.
    let totals: DogTotals?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Total(totals?.formattedCollectedLength, placeholder: "00.0 km", label: "Collected length", size: 48)
            HStack(alignment: .top) {
                Total(totals?.completedAreaCount.formatted(), placeholder: "00", label: "Areas completed", size: 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Total(totals?.completedStreetCount.formatted(), placeholder: "00", label: "Streets completed", size: 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

extension DogTotals {
    /// The collected length in kilometres, for example "12.4 km". It rounds
    /// down, like the completion.
    var formattedCollectedLength: String {
        Measurement(value: collectedLengthMetres / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(
                width: .abbreviated, usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(1)).rounded(rule: .down)))
    }
}

/// One total: a big number and its label. Without a value, the number is a
/// grey placeholder.
private struct Total: View {
    let value: String?
    let placeholder: String
    let label: LocalizedStringKey
    let size: CGFloat

    init(_ value: String?, placeholder: String, label: LocalizedStringKey, size: CGFloat) {
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
            Dashboard(totals: DogTotals(collectedLengthMetres: 12_380, completedAreaCount: 1, completedStreetCount: 14))
        }
        Section {
            Dashboard(totals: nil)
        }
    }
}
