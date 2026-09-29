//
//  DogBadge.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import SwiftUI

/// The photo of a dog in a circle, else the first letter of its name on a
/// circle in its coat colour.
struct DogBadge: View {
    let name: String
    var photo: Data?
    var coat: CoatColour = .apricot
    /// The diameter of the circle, in points.
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let image = photo.flatMap(UIImage.init(data:)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(name.prefix(1).uppercased())
                    .font(.system(size: size * 0.5, weight: .bold).width(.condensed))
                    .foregroundStyle(coat.letterColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(coat.color)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

extension DogBadge {
    init(dog: Dog, size: CGFloat = 40) {
        self.init(name: dog.name, photo: dog.photoData, coat: dog.coatColour, size: size)
    }
}
