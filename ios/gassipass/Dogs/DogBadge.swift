//
//  DogBadge.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import GassiPassCore
import SwiftUI

/// The photo of a dog in a circle, else the first letter of its name on an
/// apricot circle.
struct DogBadge: View {
    let name: String
    var photo: Data?
    /// The diameter of the circle, in points.
    var size: CGFloat = 40

    var body: some View {
        DogPortrait(name: name, photo: photo, letterSize: size * 0.5)
            .frame(width: size, height: size)
            .clipShape(.circle)
    }
}

/// The photo of a dog, or the first letter of its name on the collected
/// colour. It fills the frame that it gets.
struct DogPortrait: View {
    let name: String
    let photo: Data?
    /// The size of the letter, in points.
    let letterSize: CGFloat

    var body: some View {
        Group {
            if let image = photo.flatMap(UIImage.init(data:)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(name.prefix(1).uppercased())
                    .font(.bigFigures(size: letterSize))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.collected)
            }
        }
        .accessibilityHidden(true)
    }
}

extension DogBadge {
    init(dog: Dog, size: CGFloat = 40) {
        self.init(name: dog.name, photo: dog.photoData, size: size)
    }
}
