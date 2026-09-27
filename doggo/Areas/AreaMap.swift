//
//  AreaMap.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import SwiftUI
import UIKit

/// A small map of an area: its boundary, all its segments in grey, and the
/// segments that the dog has collected in the collected colour of the map.
/// It needs no network, as it draws only data of the map package.
struct AreaMap: View {
    /// The BFS number of the area.
    let area: Int
    let collectedSegments: Set<Segment.ID>

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(uiImage: image)
                    .resizable()
            }
            Color.clear
                .task(id: request(size: geometry.size)) {
                    let request = request(size: geometry.size)
                    guard let drawn = await AreaMapRenderer.shared.image(for: request), !Task.isCancelled
                    else { return }
                    image = drawn
                }
        }
        .accessibilityHidden(true)
    }

    private func request(size: CGSize) -> AreaMapRenderer.Request {
        AreaMapRenderer.Request(
            area: area, collectedSegments: collectedSegments, width: size.width, height: size.height,
            scale: displayScale, isDark: colorScheme == .dark)
    }
}

/// Draws the images of `AreaMap` off the main thread and keeps the recent
/// ones, so that a long list of areas scrolls smoothly.
actor AreaMapRenderer {
    static let shared = AreaMapRenderer()

    nonisolated struct Request: Hashable, Sendable {
        let area: Int
        let collectedSegments: Set<Segment.ID>
        let width: Double
        let height: Double
        let scale: Double
        let isDark: Bool

        var cacheKey: NSString {
            "\(area) \(width)x\(height)@\(scale) \(isDark) \(collectedSegments.hashValue)" as NSString
        }
    }

    /// The packages of the renderer, opened on first use. The map view reads
    /// the others on the main thread at the same time.
    private var packages: [MapPackage]?
    private let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    /// The image for the request, or nil if the task is cancelled or the
    /// packages do not hold the area.
    func image(for request: Request) -> UIImage? {
        if let image = images.object(forKey: request.cacheKey) {
            return image
        }
        guard request.width > 0, request.height > 0, !Task.isCancelled else { return nil }
        if packages == nil {
            packages = (try? MapPackage.bundled()) ?? []
        }
        guard let shape = packages?.lazy.compactMap({ try? $0.shape(of: request.area) }).first,
              !Task.isCancelled
        else { return nil }
        let image = Self.draw(shape, for: request)
        images.setObject(
            image, forKey: request.cacheKey,
            cost: Int(request.width * request.height * request.scale * request.scale * 4))
        return image
    }

    private static func draw(_ shape: AreaShape, for request: Request) -> UIImage {
        let size = CGSize(width: request.width, height: request.height)
        let traits = UITraitCollection(userInterfaceStyle: request.isDark ? .dark : .light)
        let project = projection(of: shape.boundary.flatMap { $0 }, into: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
        // Thin lines on a small map, thicker ones on a big map.
        let lineWidth = min(max(min(size.width, size.height) / 40, 1.2), 3)

        let boundary = CGMutablePath()
        for ring in shape.boundary {
            boundary.addLines(between: ring.map(project))
            boundary.closeSubpath()
        }
        let notCollected = CGMutablePath()
        let collected = CGMutablePath()
        for segment in shape.segments {
            let path = request.collectedSegments.contains(segment.id) ? collected : notCollected
            path.addLines(between: segment.coordinates.map(project))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = request.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.addPath(boundary)
            cg.setFillColor(UIColor.tertiarySystemFill.resolvedColor(with: traits).cgColor)
            cg.fillPath(using: .evenOdd)
            cg.addPath(boundary)
            cg.setStrokeColor(UIColor.systemGray3.resolvedColor(with: traits).cgColor)
            cg.setLineWidth(1)
            cg.strokePath()
            cg.addPath(notCollected)
            cg.setStrokeColor(UIColor.systemGray2.resolvedColor(with: traits).cgColor)
            cg.setLineWidth(lineWidth / 3)
            cg.strokePath()
            cg.addPath(collected)
            cg.setStrokeColor(SegmentMapView.collectedColor.resolvedColor(with: traits).cgColor)
            cg.setLineWidth(lineWidth)
            cg.strokePath()
        }
    }

    /// A function that places coordinates in the rectangle, so that the
    /// given coordinates fill it as far as possible without distortion.
    private static func projection(
        of coordinates: [CLLocationCoordinate2D], into rect: CGRect
    ) -> (CLLocationCoordinate2D) -> CGPoint {
        let longitudes = coordinates.map(\.longitude), latitudes = coordinates.map(\.latitude)
        let minLongitude = longitudes.min() ?? 0, maxLongitude = longitudes.max() ?? 0
        let minLatitude = latitudes.min() ?? 0, maxLatitude = latitudes.max() ?? 0
        // A degree of longitude is shorter than a degree of latitude away
        // from the equator.
        let xScale = cos((minLatitude + maxLatitude) / 2 * .pi / 180)
        let width = max((maxLongitude - minLongitude) * xScale, .leastNonzeroMagnitude)
        let height = max(maxLatitude - minLatitude, .leastNonzeroMagnitude)
        let pointsPerDegree = min(rect.width / width, rect.height / height)
        let offsetX = rect.minX + (rect.width - width * pointsPerDegree) / 2
        let offsetY = rect.minY + (rect.height - height * pointsPerDegree) / 2
        return { coordinate in
            CGPoint(x: offsetX + (coordinate.longitude - minLongitude) * xScale * pointsPerDegree,
                    y: offsetY + (maxLatitude - coordinate.latitude) * pointsPerDegree)
        }
    }
}
