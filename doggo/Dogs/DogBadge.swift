//
//  DogBadge.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import SwiftUI

/// The first letter of a dog's name on a yellow circle.
struct DogBadge: View {
    let name: String
    /// The diameter of the circle, in points.
    var size: CGFloat = 40

    var body: some View {
        Text(name.prefix(1).uppercased())
            .font(.system(size: size * 0.5, weight: .bold).width(.condensed))
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(Color.collected, in: .circle)
            .accessibilityHidden(true)
    }
}
