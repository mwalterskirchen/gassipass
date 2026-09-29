//
//  AreaMap.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import SwiftUI
import UIKit

/// A small map of an area: its boundary, all its segments in grey, and the
/// segments that the dog has collected in the collected colour.
/// It needs no network, as it draws only data of the map package.
struct AreaMap: View {
    /// The BFS number of the area.
    let area: Int
    /// The feature IDs (`Segment.fid`) of the collected segments of the area.
    let collectedFeatures: Set<Int>

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
            area: area, collectedFeatures: collectedFeatures, width: size.width, height: size.height,
            scale: displayScale, isDark: colorScheme == .dark)
    }
}

/// Draws the images of `AreaMap` off the main thread and keeps the recent
/// ones, so that a long list of areas scrolls smoothly.
///
/// An image has two layers. The base layer is the boundary and all segments
/// of the area, which the map build fixes, so the renderer draws it once and
/// keeps it on disk (`CacheFolder`). An area can have tens of thousands of
/// segments, so the base layer draws their lines only as fine as the pixels.
/// The top layer is the collected segments, which the renderer reads by
/// their feature IDs and draws on each change.
actor AreaMapRenderer {
    static let shared = AreaMapRenderer()

    nonisolated struct Request: Hashable, Sendable {
        let area: Int
        let collectedFeatures: Set<Int>
        let width: Double
        let height: Double
        let scale: Double
        let isDark: Bool

        var cacheKey: NSString {
            "\(baseKey) \(collectedFeatures.hashValue)" as NSString
        }

        /// The name of the base layer, which does not depend on the collected segments.
        var baseKey: String {
            "\(area) \(Int(width))x\(Int(height))@\(scale) \(isDark ? "dark" : "light")"
        }
    }

    private let packages = MapPackages.bundled
    /// The folder of the base layers, or nil until it can be made.
    private var baseFolder: URL?
    private let images = imageCache(megabytes: 48)
    private let bases = imageCache(megabytes: 32)

    /// The image for the request, or nil if the task is cancelled or the
    /// packages do not hold the area.
    func image(for request: Request) -> UIImage? {
        if let image = images.object(forKey: request.cacheKey) {
            return image
        }
        guard request.width > 0, request.height > 0, !Task.isCancelled else { return nil }
        guard let boundary = try? packages.boundary(of: request.area),
              let base = base(for: request, boundary: boundary),
              !Task.isCancelled
        else { return nil }
        let collected = request.collectedFeatures.isEmpty
            ? [] : (try? packages.segments(withFIDs: request.collectedFeatures)) ?? []
        let image = collected.isEmpty ? base : Self.draw(collected, on: base, boundary: boundary, for: request)
        images.setObject(image, forKey: request.cacheKey, cost: Self.cost(of: request))
        return image
    }

    /// The base layer of the request: from memory, else from disk, else
    /// drawn from all segments of the area and stored.
    private func base(for request: Request, boundary: [[CLLocationCoordinate2D]]) -> UIImage? {
        let key = request.baseKey as NSString
        if let image = bases.object(forKey: key) {
            return image
        }
        if baseFolder == nil {
            baseFolder = (try? packages.identity()).flatMap { CacheFolder.folder(of: "AreaMaps", packages: $0) }
        }
        let file = baseFolder?.appending(path: request.baseKey + ".png")
        var image = file.flatMap { try? Data(contentsOf: $0) }
            .flatMap { UIImage(data: $0, scale: request.scale) }
            .flatMap { $0.preparingForDisplay() }
        if image == nil {
            guard let shape = try? packages.shape(of: request.area), !Task.isCancelled else { return nil }
            let drawn = Self.drawBase(shape, for: request)
            if let file, let data = drawn.pngData() {
                try? data.write(to: file, options: .atomic)
            }
            image = drawn
        }
        if let image {
            bases.setObject(image, forKey: key, cost: Self.cost(of: request))
        }
        return image
    }

    private static func imageCache(megabytes: Int) -> NSCache<NSString, UIImage> {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = megabytes * 1024 * 1024
        return cache
    }

    private static func cost(of request: Request) -> Int {
        Int(request.width * request.height * request.scale * request.scale * 4)
    }

    /// Thin lines on a small map, thicker ones on a big map.
    private static func lineWidth(for request: Request) -> Double {
        min(max(min(request.width, request.height) / 40, 1.2), 3)
    }

    private static func renderer(for request: Request) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = request.scale
        return UIGraphicsImageRenderer(size: CGSize(width: request.width, height: request.height), format: format)
    }

    private static func projection(
        of boundary: [[CLLocationCoordinate2D]], for request: Request
    ) -> (CLLocationCoordinate2D) -> CGPoint {
        projection(of: boundary.flatMap { $0 },
                   into: CGRect(x: 0, y: 0, width: request.width, height: request.height).insetBy(dx: 1, dy: 1))
    }

    /// The boundary of the area and all its segments in grey.
    private static func drawBase(_ shape: AreaShape, for request: Request) -> UIImage {
        let traits = UITraitCollection(userInterfaceStyle: request.isDark ? .dark : .light)
        let project = projection(of: shape.boundary, for: request)
        // Points closer than this to the point before them add nothing that
        // the pixels can show.
        let tolerance = 0.5 / request.scale

        let boundary = CGMutablePath()
        for ring in shape.boundary {
            boundary.addLines(between: ring.map(project))
            boundary.closeSubpath()
        }
        let segments = CGMutablePath()
        for segment in shape.segments {
            segments.addLines(between: simplified(segment.coordinates.map(project), tolerance: tolerance))
        }

        return renderer(for: request).image { context in
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
            cg.addPath(segments)
            cg.setStrokeColor(UIColor.systemGray2.resolvedColor(with: traits).cgColor)
            cg.setLineWidth(lineWidth(for: request) / 3)
            cg.strokePath()
        }
    }

    /// The collected segments in the collected colour, on the base layer.
    private static func draw(
        _ collected: [Segment], on base: UIImage, boundary: [[CLLocationCoordinate2D]], for request: Request
    ) -> UIImage {
        let traits = UITraitCollection(userInterfaceStyle: request.isDark ? .dark : .light)
        let project = projection(of: boundary, for: request)
        let lineWidth = lineWidth(for: request)
        let path = CGMutablePath()
        for segment in collected {
            path.addLines(between: segment.coordinates.map(project))
        }

        func color(_ name: String) -> CGColor {
            (UIColor(named: name) ?? .systemOrange).resolvedColor(with: traits).cgColor
        }

        return renderer(for: request).image { context in
            base.draw(at: .zero)
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            // A dark edge keeps the apricot visible on a light background.
            cg.addPath(path)
            cg.setStrokeColor(color("CollectedEdge"))
            cg.setLineWidth(lineWidth + 1.2)
            cg.strokePath()
            cg.addPath(path)
            cg.setStrokeColor(color("Collected"))
            cg.setLineWidth(lineWidth)
            cg.strokePath()
        }
    }

    /// The points without those closer than the tolerance to the last point
    /// kept. The first and the last point always stay.
    private static func simplified(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var kept = [points[0]]
        for point in points.dropFirst().dropLast() {
            let last = kept[kept.count - 1]
            if hypot(point.x - last.x, point.y - last.y) >= tolerance {
                kept.append(point)
            }
        }
        kept.append(points[points.count - 1])
        return kept
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
