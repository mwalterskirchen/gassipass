//
//  HomeBasePin.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 11.11.2026.
//

import SwiftUI

/// The pin of the home base, whose tip marks the centre of the map.
struct HomeBasePin: View {
    var body: some View {
        Image(systemName: "mappin")
            .font(.system(size: 36, weight: .semibold))
            .foregroundStyle(Color.forest)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            // The tip of the symbol is at its bottom.
            .offset(y: -18)
            .accessibilityHidden(true)
    }
}
