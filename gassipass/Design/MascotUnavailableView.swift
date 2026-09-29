//
//  MascotUnavailableView.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import SwiftUI

/// An empty screen with the mascot above the title, and a description that
/// says what to do.
struct MascotUnavailableView: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    init(_ title: LocalizedStringKey, description: LocalizedStringKey) {
        self.title = title
        self.description = description
    }

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                Image(.mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96)
                    .accessibilityHidden(true)
                Text(title)
            }
        } description: {
            Text(description)
        }
    }
}

#Preview {
    MascotUnavailableView("No Walks", description: "Your walks appear here.")
}
