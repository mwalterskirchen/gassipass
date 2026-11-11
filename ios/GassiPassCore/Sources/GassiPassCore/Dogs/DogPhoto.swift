//
//  DogPhoto.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The photo of a dog. The app stores a small copy of the chosen photo, so
/// that the store and its upload stay small.
public enum DogPhoto {
    /// The length of the long side of a stored photo, in pixels.
    public nonisolated static let maxPixels = 600

    /// A JPEG of the photo, with the long side at most `maxPixels`, or nil if
    /// the data is not an image.
    public nonisolated static func storedData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // The small copy is upright, and it is never larger than the photo.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let stored = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(stored, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? stored as Data : nil
    }
}
