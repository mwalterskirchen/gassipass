//
//  SegmentMapView.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import MapLibre
import SwiftUI

/// The swisstopo light base map with the segments of the map package on top,
/// each one coloured as collected or not collected, and the track of a walk
/// above them. The map frames the track if there is one, and else all
/// segments.
///
/// The base map loads online. Sometimes its style cannot load, for example
/// without a network. Then the map switches to a bundled style with a plain
/// background. The segments stay visible on it.
struct SegmentMapView: UIViewRepresentable {
    static let baseMapStyle = URL(
        string: "https://vectortiles.geo.admin.ch/styles/ch.swisstopo.lightbasemap.vt/style.json")!
    static let offlineStyle = Bundle.main.url(forResource: "OfflineStyle", withExtension: "json")!
    static let collectedColor = UIColor.systemGreen
    static let notCollectedColor = UIColor.systemOrange

    let segments: [Segment]
    var track: [CLLocationCoordinate2D] = []
    var collectedSegmentIDs: Set<Segment.ID> = []

    func makeCoordinator() -> Coordinator {
        Coordinator(segments: segments, track: track, collectedSegmentIDs: collectedSegmentIDs)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = FramingMapView(frame: .zero, styleURL: Self.baseMapStyle)
        mapView.boundsToFrame = Self.bounds(of: track.isEmpty ? segments.flatMap(\.coordinates) : track)
        mapView.delegate = context.coordinator
        // MapAttribution shows the full attribution that the base map needs.
        mapView.attributionButton.isHidden = true
        mapView.logoView.isHidden = true
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.show(collectedSegmentIDs: collectedSegmentIDs)
    }

    private static func bounds(of coordinates: [CLLocationCoordinate2D]) -> MLNCoordinateBounds? {
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
        private let track: [CLLocationCoordinate2D]
        private var collectedSegmentIDs: Set<Segment.ID>
        private var source: MLNShapeSource?

        init(segments: [Segment], track: [CLLocationCoordinate2D], collectedSegmentIDs: Set<Segment.ID>) {
            self.segments = segments
            self.track = track
            self.collectedSegmentIDs = collectedSegmentIDs
        }

        func show(collectedSegmentIDs: Set<Segment.ID>) {
            guard collectedSegmentIDs != self.collectedSegmentIDs else { return }
            self.collectedSegmentIDs = collectedSegmentIDs
            source?.shape = MLNShapeCollectionFeature(shapes: features())
        }

        private func features() -> [MLNPolylineFeature] {
            segments.map { segment in
                var coordinates = segment.coordinates
                let feature = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
                feature.identifier = segment.id
                feature.attributes = ["collected": collectedSegmentIDs.contains(segment.id)]
                return feature
            }
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            let source = MLNShapeSource(identifier: "segments", features: features(), options: nil)
            style.addSource(source)
            self.source = source

            let layer = MLNLineStyleLayer(identifier: "segments", source: source)
            layer.lineColor = NSExpression(
                format: "TERNARY(collected == YES, %@, %@)",
                SegmentMapView.collectedColor, SegmentMapView.notCollectedColor)
            layer.lineWidth = NSExpression(
                forMLNInterpolating: .zoomLevelVariable, curveType: .linear, parameters: nil,
                stops: NSExpression(forConstantValue: [12: 1.5, 16: 4, 18: 8]))
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            addBelowLabels(layer, to: style)

            guard track.count > 1 else { return }
            var coordinates = track
            let trackSource = MLNShapeSource(
                identifier: "track",
                shape: MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count)),
                options: nil)
            style.addSource(trackSource)
            let trackLayer = MLNLineStyleLayer(identifier: "track", source: trackSource)
            trackLayer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
            trackLayer.lineWidth = NSExpression(forConstantValue: 4)
            trackLayer.lineCap = NSExpression(forConstantValue: "round")
            trackLayer.lineJoin = NSExpression(forConstantValue: "round")
            addBelowLabels(trackLayer, to: style)
        }

        /// Keeps the labels of the base map readable above the lines.
        private func addBelowLabels(_ layer: MLNStyleLayer, to style: MLNStyle) {
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
