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
/// With `shownSegments`, the map loads nothing and shows only those segments,
/// as not collected.
///
/// The base map loads online. In dark mode the map shows a dark version of
/// it (`DarkMapStyle`). Sometimes the style cannot load, for example without
/// a network. Then the map switches to a bundled style with a plain
/// background. The segments stay visible on it.
struct SegmentMapView: UIViewRepresentable {
    static let baseMapStyle = URL(
        string: "https://vectortiles.geo.admin.ch/styles/ch.swisstopo.lightbasemap.vt/style.json")!
    static let offlineStyle = Bundle.main.url(forResource: "OfflineStyle", withExtension: "json")!
    /// The layers of the segments, from bottom to top.
    static let segmentLayers = ["segments-not-collected", "segments-collected-edge", "segments-collected"]

    /// Where the map starts without a track until the location is known, or
    /// when the walker does not share it: Dietikon, the first test area.
    static let startCenter = CLLocationCoordinate2D(latitude: 47.4035, longitude: 8.4000)
    static let startZoomLevel = 14.0

    /// Below this zoom level the map shows no segments.
    static let minimumSegmentZoomLevel = 12.0

    var packages: [MapPackage] = []
    var shownSegments: [Segment]?
    var track: [CLLocationCoordinate2D] = []
    var collectedSegmentIDs: Set<Segment.ID> = []
    /// The zoom level at the start, when the map follows the walker.
    var zoomLevel = startZoomLevel
    /// Gets the BFS number of the area of a tapped segment.
    var onSelectArea: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(packages: packages, shownSegments: shownSegments, track: track,
                    collectedSegmentIDs: collectedSegmentIDs)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = FramingMapView(frame: .zero, styleURL: Self.offlineStyle)
        if track.isEmpty {
            mapView.setCenter(Self.startCenter, zoomLevel: zoomLevel, animated: false)
            mapView.showsUserLocation = true
            // The map stops following when the walker moves the map.
            mapView.userTrackingMode = .follow
        } else {
            mapView.boundsToFrame = Self.bounds(of: track)
        }
        mapView.delegate = context.coordinator
        // A style from JSON loads at once, so the delegate must be set first.
        context.coordinator.showStyle(isDark: context.environment.colorScheme == .dark, on: mapView)
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
        context.coordinator.showStyle(isDark: context.environment.colorScheme == .dark, on: mapView)
        context.coordinator.show(collectedSegmentIDs: collectedSegmentIDs, shownSegments: shownSegments)
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
        private var shownSegments: [Segment]?
        private let track: [CLLocationCoordinate2D]
        private var collectedSegmentIDs: Set<Segment.ID>
        private var segmentSource: MLNShapeSource?
        /// The box whose segments the source holds, or nil if it holds none.
        private var loadedBox: CoordinateBox?
        private var loadedSegments: [Segment] = []
        var onSelectArea: ((Int) -> Void)?
        /// Whether the map shows the dark style, or nil before the first style.
        private var isDark: Bool?
        private var isShowingOfflineStyle = false
        /// The dark style that the map shows, or nil if it shows another style.
        private var shownDarkStyle: String?

        /// The dark style of the last download.
        private static var darkStyle = DarkMapStyle.stored()
        /// The download of the dark style, once for each launch of the app.
        private static var darkStyleDownload: Task<String?, Never>?

        init(packages: [MapPackage], shownSegments: [Segment]?, track: [CLLocationCoordinate2D],
             collectedSegmentIDs: Set<Segment.ID>) {
            self.packages = packages
            self.shownSegments = shownSegments
            self.track = track
            self.collectedSegmentIDs = collectedSegmentIDs
        }

        func show(collectedSegmentIDs: Set<Segment.ID>, shownSegments: [Segment]?) {
            if let shownSegments {
                guard shownSegments.map(\.id) != self.shownSegments?.map(\.id) else { return }
                self.shownSegments = shownSegments
                segmentSource?.shape = MLNShapeCollectionFeature(shapes: features(of: shownSegments))
                return
            }
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

        /// Shows the light base map, or its dark version. The dark version
        /// opens at once from the last download, and changes when a new
        /// download differs from it.
        func showStyle(isDark: Bool, on mapView: MLNMapView) {
            guard isDark != self.isDark else { return }
            self.isDark = isDark
            isShowingOfflineStyle = false
            shownDarkStyle = nil
            guard isDark else {
                mapView.styleURL = SegmentMapView.baseMapStyle
                return
            }
            if let style = Self.darkStyle {
                show(darkStyle: style, on: mapView)
            } else {
                showOfflineStyle(on: mapView)
            }
            Task { [weak self, weak mapView] in
                guard let style = await Self.downloadDarkStyle(), let self, let mapView,
                      self.isDark == true, style != self.shownDarkStyle
                else { return }
                show(darkStyle: style, on: mapView)
            }
        }

        private func show(darkStyle: String, on mapView: MLNMapView) {
            isShowingOfflineStyle = false
            shownDarkStyle = darkStyle
            mapView.styleJSON = darkStyle
        }

        private func showOfflineStyle(on mapView: MLNMapView) {
            isShowingOfflineStyle = true
            shownDarkStyle = nil
            if isDark == true, let data = try? Data(contentsOf: SegmentMapView.offlineStyle),
               let style = try? DarkMapStyle.darkened(data) {
                mapView.styleJSON = style
            } else {
                mapView.styleURL = SegmentMapView.offlineStyle
            }
        }

        /// The new dark style, or nil if it cannot download.
        private static func downloadDarkStyle() async -> String? {
            let download = darkStyleDownload
                ?? Task { try? await DarkMapStyle.download(from: SegmentMapView.baseMapStyle) }
            darkStyleDownload = download
            guard let style = await download.value else { return nil }
            darkStyle = style
            return style
        }

        /// The colour of the asset catalogue for the style of the map.
        private func color(_ name: String) -> UIColor {
            resolved(UIColor(named: name) ?? .systemYellow)
        }

        private func resolved(_ color: UIColor) -> UIColor {
            color.resolvedColor(with: UITraitCollection(userInterfaceStyle: isDark == true ? .dark : .light))
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            let source = MLNShapeSource(identifier: "segments", shape: nil, options: nil)
            style.addSource(source)
            segmentSource = source
            loadedBox = nil
            if let shownSegments {
                source.shape = MLNShapeCollectionFeature(shapes: features(of: shownSegments))
            } else {
                loadSegments(for: mapView)
            }

            // Segments to collect are dashed, like paths on a hiking map.
            // Collected segments are solid, with a dark edge that keeps the
            // yellow visible on the light base map.
            addLine("segments-not-collected", from: source, where: "collected == NO",
                    color: color("NotCollected"), widths: [12: 0.8, 16: 2, 18: 3.5],
                    dashes: [2.5, 2], opacity: 0.6, to: style)
            addLine("segments-collected-edge", from: source, where: "collected == YES",
                    color: color("CollectedEdge"), widths: [12: 2.6, 16: 6.5, 18: 11], to: style)
            addLine("segments-collected", from: source, where: "collected == YES",
                    color: color("Collected"), widths: [12: 1.6, 16: 4.5, 18: 8], to: style)

            guard track.count > 1 else { return }
            var coordinates = track
            let trackSource = MLNShapeSource(
                identifier: "track",
                shape: MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count)),
                options: nil)
            style.addSource(trackSource)
            let edge = isDark == true ? UIColor(white: 0.1, alpha: 1) : .white
            addLine("track-edge", from: trackSource, color: edge, widths: [12: 5, 16: 8, 18: 11], to: style)
            addLine("track", from: trackSource, color: resolved(.systemBlue), widths: [12: 3, 16: 5, 18: 7], to: style)
        }

        private func addLine(
            _ identifier: String, from source: MLNSource, where predicate: String? = nil, color: UIColor,
            widths: [Double: Double], dashes: [Double]? = nil, opacity: Double = 1, to style: MLNStyle
        ) {
            let layer = MLNLineStyleLayer(identifier: identifier, source: source)
            layer.predicate = predicate.map { NSPredicate(format: $0) }
            layer.lineColor = NSExpression(forConstantValue: color)
            layer.lineOpacity = NSExpression(forConstantValue: opacity)
            layer.lineWidth = NSExpression(
                forMLNInterpolating: .zoomLevelVariable, curveType: .linear, parameters: nil,
                stops: NSExpression(forConstantValue: widths))
            if let dashes {
                layer.lineDashPattern = NSExpression(forConstantValue: dashes)
            } else {
                layer.lineCap = NSExpression(forConstantValue: "round")
            }
            layer.lineJoin = NSExpression(forConstantValue: "round")
            addBelowLabels(layer, to: style)
        }

        /// Selects the area of the segment under the tap, or else of a
        /// segment near it, so that a thin line is easy to hit.
        @objc func selectArea(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MLNMapView, let onSelectArea else { return }
            let point = recognizer.location(in: mapView)
            let layers = Set(SegmentMapView.segmentLayers)
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
            guard let segmentSource, shownSegments == nil else { return }
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
            guard !isShowingOfflineStyle else { return }
            showOfflineStyle(on: mapView)
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
