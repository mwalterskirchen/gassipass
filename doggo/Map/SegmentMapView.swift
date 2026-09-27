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
/// each one coloured as collected or not collected, and the track of a walk
/// above them. The map frames the track if there is
/// one, and else follows the walker's location. With `onSelectArea`, a tap on
/// a segment selects the area that the segment lies in.
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
    nonisolated static let collectedColor = UIColor.systemGreen
    static let notCollectedColor = UIColor.systemOrange

    /// Where the map starts without a track until the location is known, or
    /// when the walker does not share it: Dietikon, the first test area.
    static let startCenter = CLLocationCoordinate2D(latitude: 47.4035, longitude: 8.4000)
    static let startZoomLevel = 14.0

    /// Below this zoom level the map shows no segments.
    static let minimumSegmentZoomLevel = 12.0

    let packages: [MapPackage]
    var track: [CLLocationCoordinate2D] = []
    var collectedSegmentIDs: Set<Segment.ID> = []
    /// Gets the BFS number of the area of a tapped segment.
    var onSelectArea: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(packages: packages, track: track, collectedSegmentIDs: collectedSegmentIDs)
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
        if onSelectArea != nil {
            let tap = UITapGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.selectArea(_:)))
            // A double tap zooms and selects nothing.
            for recognizer in mapView.gestureRecognizers ?? []
            where (recognizer as? UITapGestureRecognizer)?.numberOfTapsRequired == 2 {
                tap.require(toFail: recognizer)
            }
            mapView.addGestureRecognizer(tap)
        }
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.onSelectArea = onSelectArea
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
        private let packages: [MapPackage]
        private let track: [CLLocationCoordinate2D]
        private var collectedSegmentIDs: Set<Segment.ID>
        private var segmentSource: MLNShapeSource?
        /// The box whose segments the source holds, or nil if it holds none.
        private var loadedBox: CoordinateBox?
        private var loadedSegments: [Segment] = []
        var onSelectArea: ((Int) -> Void)?

        init(packages: [MapPackage], track: [CLLocationCoordinate2D], collectedSegmentIDs: Set<Segment.ID>) {
            self.packages = packages
            self.track = track
            self.collectedSegmentIDs = collectedSegmentIDs
        }

        func show(collectedSegmentIDs: Set<Segment.ID>) {
            guard collectedSegmentIDs != self.collectedSegmentIDs else { return }
            self.collectedSegmentIDs = collectedSegmentIDs
            guard loadedBox != nil else { return }
            segmentSource?.shape = MLNShapeCollectionFeature(shapes: features(of: loadedSegments))
        }

        private func features(of segments: [Segment]) -> [MLNPolylineFeature] {
            segments.map { segment in
                var coordinates = segment.coordinates
                let feature = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
                feature.identifier = segment.id
                feature.attributes = ["collected": collectedSegmentIDs.contains(segment.id), "area": segment.area]
                return feature
            }
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            let source = MLNShapeSource(identifier: "segments", shape: nil, options: nil)
            style.addSource(source)
            segmentSource = source
            loadedBox = nil
            loadSegments(for: mapView)

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

        /// Selects the area of the segment under the tap, or else of a
        /// segment near it, so that a thin line is easy to hit.
        @objc func selectArea(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MLNMapView, let onSelectArea else { return }
            let point = recognizer.location(in: mapView)
            let layers: Set<String> = ["segments"]
            let features = mapView.visibleFeatures(at: point, styleLayerIdentifiers: layers)
                + mapView.visibleFeatures(
                    in: CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44),
                    styleLayerIdentifiers: layers)
            guard let area = features.lazy.compactMap({ $0.attribute(forKey: "area") as? NSNumber }).first
            else { return }
            onSelectArea(area.intValue)
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
                loadedSegments = []
                return
            }
            let visible = mapView.visibleCoordinateBounds
            let visibleBox = CoordinateBox(
                minLongitude: visible.sw.longitude, maxLongitude: visible.ne.longitude,
                minLatitude: visible.sw.latitude, maxLatitude: visible.ne.latitude)
            if let loadedBox, loadedBox.contains(visibleBox) { return }

            let box = visibleBox.expanded(by: 0.5)
            loadedSegments = packages.flatMap { package in
                (try? package.segments(in: box)) ?? []
            }
            segmentSource.shape = MLNShapeCollectionFeature(shapes: features(of: loadedSegments))
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
