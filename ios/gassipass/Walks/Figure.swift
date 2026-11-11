//
//  Figure.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 11.11.2026.
//

import SwiftUI

/// A big number with a small label below it.
struct Figure: View {
    let value: String
    let label: LocalizedStringKey
    let alignment: HorizontalAlignment

    init(_ value: String, label: LocalizedStringKey, alignment: HorizontalAlignment = .leading) {
        self.value = value
        self.label = label
        self.alignment = alignment
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(value)
                .bigFigure(size: 40)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
