//
//  DogPhoto.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import SwiftUI
import UIKit

/// The photo of a dog. The app stores a small copy of the chosen photo, so
/// that the store and its sync stay small.
enum DogPhoto {
    /// The length of the long side of a stored photo, in pixels.
    static let maxPixels: CGFloat = 600

    /// A JPEG of the photo, with the long side at most `maxPixels`, or nil if
    /// the data is not an image.
    nonisolated static func storedData(from data: Data) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let factor = min(maxPixels / max(pixels.width, pixels.height), 1)
        let size = CGSize(width: (pixels.width * factor).rounded(), height: (pixels.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.8) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
