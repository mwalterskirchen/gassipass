//
//  SegmentMapView.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import MapLibre
import SwiftUI

/// The swisstopo light base map with the segments of the map packages on top,
/// and the track of a walk above them. The map frames the track if there is
/// one, and else follows the walker's location.
///
/// The packages hold too many segments to draw at once. The map loads only
/// the segments near the visible region, and none when it is zoomed out far.
///
/// The base map loads online. Sometimes its style cannot load, for example
/// without a network. Then the map switches to a bundled style with a plain
/// background. The segments stay visible on it.
struct SegmentMapView: UIViewRepresentable {
    static let baseMapStyle = URL(
        string: "https://vectortiles.geo.admin.ch/styles/ch.swisstopo.lightbasemap.vt/style.json")!
    static let offlineStyle = Bundle.main.url(forResource: "OfflineStyle", withExtension: "json")!

    /// Where the map starts without a track until the location is known, or
    /// when the walker does not share it: Dietikon, the first test area.
    static let startCenter = CLLocationCoordinate2D(latitude: 47.4035, longitude: 8.4000)
    static let startZoomLevel = 14.0

    /// Below this zoom level the map shows no segments.
    static let minimumSegmentZoomLevel = 12.0

    let packages: [MapPackage]
    var track: [CLLocationCoordinate2D] = []

    func makeCoordinator() -> Coordinator {
        Coordinator(packages: packages, track: track)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = FramingMapView(frame: .zero, styleURL: Self.baseMapStyle)
        if track.isEmpty {
            mapView.setCenter(Self.startCenter, zoomLevel: Self.startZoomLevel, animated: false)
            mapView.showsUserLocation = true
            // The map stops following when the walker moves the map.
            mapView.userTrackingMode = .follow
        } else {
            mapView.boundsToFrame = Self.bounds(of: track)
        }
        mapView.delegate = context.coordinator
        // MapAttribution shows the full attribution that the base map needs.
        mapView.attributionButton.isHidden = true
        mapView.logoView.isHidden = true
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {}

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
        private let packages: [MapPackage]
        private let track: [CLLocationCoordinate2D]
        private var segmentSource: MLNShapeSource?
        /// The box whose segments the source holds, or nil if it holds none.
        private var loadedBox: CoordinateBox?

        init(packages: [MapPackage], track: [CLLocationCoordinate2D]) {
            self.packages = packages
            self.track = track
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            let source = MLNShapeSource(identifier: "segments", shape: nil, options: nil)
            style.addSource(source)
            segmentSource = source
            loadedBox = nil
            loadSegments(for: mapView)

            let layer = MLNLineStyleLayer(identifier: "segments", source: source)
            layer.lineColor = NSExpression(forConstantValue: UIColor.systemOrange)
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

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            loadSegments(for: mapView)
        }

        /// Loads the segments of a box around the visible region, unless the
        /// source already holds them.
        private func loadSegments(for mapView: MLNMapView) {
            guard let segmentSource else { return }
            guard mapView.zoomLevel >= SegmentMapView.minimumSegmentZoomLevel else {
                segmentSource.shape = nil
                loadedBox = nil
                return
            }
            let visible = mapView.visibleCoordinateBounds
            let visibleBox = CoordinateBox(
                minLongitude: visible.sw.longitude, maxLongitude: visible.ne.longitude,
                minLatitude: visible.sw.latitude, maxLatitude: visible.ne.latitude)
            if let loadedBox, loadedBox.contains(visibleBox) { return }

            let box = visibleBox.expanded(by: 0.5)
            let features = packages.flatMap { package in
                (try? package.segments(in: box)) ?? []
            }.map { segment in
                var coordinates = segment.coordinates
                let feature = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
                feature.identifier = segment.id
                return feature
            }
            segmentSource.shape = MLNShapeCollectionFeature(shapes: features)
            loadedBox = box
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
