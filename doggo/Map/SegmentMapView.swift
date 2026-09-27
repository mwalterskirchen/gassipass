//
//  SegmentMapView.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import MapLibre
import SwiftUI

/// The swisstopo light base map with the segments of the map package on top.
///
/// The base map loads online. Sometimes its style cannot load, for example
/// without a network. Then the map switches to a bundled style with a plain
/// background. The segments stay visible on it.
struct SegmentMapView: UIViewRepresentable {
    static let baseMapStyle = URL(
        string: "https://vectortiles.geo.admin.ch/styles/ch.swisstopo.lightbasemap.vt/style.json")!
    static let offlineStyle = Bundle.main.url(forResource: "OfflineStyle", withExtension: "json")!

    let segments: [Segment]

    func makeCoordinator() -> Coordinator {
        Coordinator(segments: segments)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = FramingMapView(frame: .zero, styleURL: Self.baseMapStyle)
        mapView.boundsToFrame = Self.bounds(of: segments)
        mapView.delegate = context.coordinator
        // MapAttribution shows the full attribution that the base map needs.
        mapView.attributionButton.isHidden = true
        mapView.logoView.isHidden = true
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {}

    private static func bounds(of segments: [Segment]) -> MLNCoordinateBounds? {
        let coordinates = segments.flatMap(\.coordinates)
        guard let first = coordinates.first else { return nil }
        var bounds = MLNCoordinateBounds(sw: first, ne: first)
        for coordinate in coordinates {
            bounds.sw.latitude = min(bounds.sw.latitude, coordinate.latitude)
            bounds.sw.longitude = min(bounds.sw.longitude, coordinate.longitude)
            bounds.ne.latitude = max(bounds.ne.latitude, coordinate.latitude)
            bounds.ne.longitude = max(bounds.ne.longitude, coordinate.longitude)
        }
        return bounds
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private let segments: [Segment]

        init(segments: [Segment]) {
            self.segments = segments
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            let features = segments.map { segment in
                var coordinates = segment.coordinates
                let feature = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
                feature.identifier = segment.id
                return feature
            }
            let source = MLNShapeSource(identifier: "segments", features: features, options: nil)
            style.addSource(source)

            let layer = MLNLineStyleLayer(identifier: "segments", source: source)
            layer.lineColor = NSExpression(forConstantValue: UIColor.systemOrange)
            layer.lineWidth = NSExpression(
                forMLNInterpolating: .zoomLevelVariable, curveType: .linear, parameters: nil,
                stops: NSExpression(forConstantValue: [12: 1.5, 16: 4, 18: 8]))
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            // Keep the labels of the base map readable above the segments.
            if let firstLabels = style.layers.first(where: { $0 is MLNSymbolStyleLayer }) {
                style.insertLayer(layer, below: firstLabels)
            } else {
                style.addLayer(layer)
            }
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: any Error) {
            guard mapView.styleURL != SegmentMapView.offlineStyle else { return }
            mapView.styleURL = SegmentMapView.offlineStyle
        }
    }
}

/// A map view that frames the given bounds once, as soon as it has a size.
private final class FramingMapView: MLNMapView {
    var boundsToFrame: MLNCoordinateBounds?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let bounds = boundsToFrame, !self.bounds.isEmpty else { return }
        boundsToFrame = nil
        setVisibleCoordinateBounds(
            bounds, edgePadding: UIEdgeInsets(top: 40, left: 20, bottom: 60, right: 20),
            animated: false, completionHandler: nil)
    }
}
