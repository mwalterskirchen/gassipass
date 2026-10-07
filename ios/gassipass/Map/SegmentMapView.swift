//
//  SegmentMapView.swift
//  gassipass
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
/// The map draws the segments from the vector tiles of the map packages,
/// and none when it is zoomed out far. MapLibre loads, caches and draws only
/// the tiles that it needs. The collected segments are a filter on the
/// feature IDs of the tiles, so a new collection changes only the filter.
/// With `shownSegments`, the map shows only those segments, as not
/// collected. Their features build off the main thread.
///
/// The base map loads online. In dark mode the map shows a dark version of
/// it (`DarkMapStyle`). Sometimes the style cannot load, for example without
/// a network. Then the map switches to a bundled style with a plain
/// background. The segments stay visible on it.
struct SegmentMapView: UIViewRepresentable {
    static let baseMapStyle = URL(
        string: "https://vectortiles.geo.admin.ch/styles/ch.swisstopo.lightbasemap.vt/style.json")!
    static let offlineStyle = Bundle.main.url(forResource: "OfflineStyle", withExtension: "json")!
    static let notCollectedLayer = "segments-not-collected"
    static let collectedEdgeLayer = "segments-collected-edge"
    static let collectedLayer = "segments-collected"

    /// Where the map starts without a track until the location is known, or
    /// when the walker does not share it: Dietikon, the first test area.
    static let startCenter = CLLocationCoordinate2D(latitude: 47.4035, longitude: 8.4000)
    static let startZoomLevel = 14.0

    var shownSegments: [Segment]?
    var track: [CLLocationCoordinate2D] = []
    /// The feature IDs of the collected segments (`Segment.fid`).
    var collectedFeatures: Set<Int> = []
    /// The zoom level at the start, when the map follows the walker.
    var zoomLevel = startZoomLevel
    /// Gets the BFS number of the area of a tapped segment.
    var onSelectArea: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(shownSegments: shownSegments, track: track, collectedFeatures: collectedFeatures)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let isDark = context.environment.colorScheme == .dark
        // The light base map starts to load at once. The dark style loads
        // from JSON below, so it starts on the small bundled style.
        let mapView = FramingMapView(frame: .zero, styleURL: isDark ? Self.offlineStyle : Self.baseMapStyle)
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
        context.coordinator.showStyle(isDark: isDark, on: mapView)
        // MapAttribution shows the attribution that the base map needs.
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
        context.coordinator.show(collectedFeatures: collectedFeatures, shownSegments: shownSegments)
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
        private var shownSegments: [Segment]?
        private let track: [CLLocationCoordinate2D]
        private var collectedFeatures: Set<Int>
        /// The source of `shownSegments`, or nil if the map shows the tiles.
        private var segmentSource: MLNShapeSource?
        /// The layers of the tiles that show the collected segments, and the
        /// layers that show the other segments.
        private var collectedLayers: [MLNStyleLayer] = []
        private var notCollectedLayers: [MLNStyleLayer] = []
        /// All layers of segments, for a tap on the map.
        private var segmentLayerIDs: Set<String> = []
        /// The update of the source that runs, if any. A newer update cancels it.
        private var update: Task<Void, Never>?
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

        init(shownSegments: [Segment]?, track: [CLLocationCoordinate2D], collectedFeatures: Set<Int>) {
            self.shownSegments = shownSegments
            self.track = track
            self.collectedFeatures = collectedFeatures
        }

        func show(collectedFeatures: Set<Int>, shownSegments: [Segment]?) {
            if let shownSegments {
                guard shownSegments.map(\.id) != self.shownSegments?.map(\.id) else { return }
                self.shownSegments = shownSegments
                guard segmentSource != nil else { return }
                showSegments(shownSegments)
                return
            }
            guard collectedFeatures != self.collectedFeatures else { return }
            self.collectedFeatures = collectedFeatures
            filterCollected()
        }

        /// Shows the segments in the source. Their features build off the
        /// main thread, and a newer update cancels a running one.
        private func showSegments(_ segments: [Segment]) {
            update?.cancel()
            update = Task { [weak self] in
                let features = await SegmentMapView.features(of: segments)
                guard !Task.isCancelled, let self else { return }
                segmentSource?.shape = features
            }
        }

        /// Sets the filters of the layers of the tiles to the collected segments of now.
        private func filterCollected() {
            // A filter on an empty list is not valid, and no segment has the fid 0.
            let features = collectedFeatures.isEmpty ? [0] : Array(collectedFeatures)
            let collected = NSPredicate(format: "$featureIdentifier IN %@", features)
            let notCollected = NSPredicate(format: "NOT ($featureIdentifier IN %@)", features)
            collectedLayers.forEach { ($0 as? MLNVectorStyleLayer)?.predicate = collected }
            notCollectedLayers.forEach { ($0 as? MLNVectorStyleLayer)?.predicate = notCollected }
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
                // The map starts on the light base map, which then needs no second load.
                if mapView.styleURL != SegmentMapView.baseMapStyle {
                    mapView.styleURL = SegmentMapView.baseMapStyle
                }
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
            resolved(UIColor(named: name) ?? .systemOrange)
        }

        private func resolved(_ color: UIColor) -> UIColor {
            color.resolvedColor(with: UITraitCollection(userInterfaceStyle: isDark == true ? .dark : .light))
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            // A new style has new sources and layers.
            update?.cancel()
            segmentSource = nil
            collectedLayers = []
            notCollectedLayers = []
            segmentLayerIDs = []
            if let shownSegments {
                let source = MLNShapeSource(identifier: "segments", shape: nil, options: nil)
                style.addSource(source)
                segmentSource = source
                addNotCollectedLine(SegmentMapView.notCollectedLayer, from: source, to: style)
                showSegments(shownSegments)
            } else {
                for source in MapPackages.bundled.tileSources {
                    addTiles(of: source, to: style)
                }
                filterCollected()
            }
            guard track.count > 1 else { return }
            var coordinates = track
            let trackSource = MLNShapeSource(
                identifier: "track",
                shape: MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count)),
                options: nil)
            style.addSource(trackSource)
            // The track is thinner than a collected segment, so that the
            // segments that the walk collected show around it.
            let edge = isDark == true ? UIColor(white: 0.1, alpha: 1) : .white
            addLine("track-edge", from: trackSource, color: edge, widths: [12: 2.5, 16: 4, 18: 5.5], to: style)
            addLine("track", from: trackSource, color: color("Track"), widths: [12: 1.5, 16: 2.5, 18: 3.5], to: style)
        }

        /// Adds the tiles of a map package as a source, with a layer for the
        /// segments that are not collected and two layers for the collected
        /// segments. The filters of the layers come from `filterCollected()`.
        private func addTiles(of tiles: MapPackages.TileSource, to style: MLNStyle) {
            let name = tiles.name
            let source = MLNVectorTileSource(identifier: "segments-\(name)", configurationURL: tiles.url)
            style.addSource(source)
            notCollectedLayers.append(
                addNotCollectedLine("\(SegmentMapView.notCollectedLayer)-\(name)", from: source, to: style))
            // Collected segments are solid, with a dark edge that keeps the
            // apricot visible on the light base map.
            collectedLayers.append(addLine(
                "\(SegmentMapView.collectedEdgeLayer)-\(name)", from: source,
                color: color("CollectedEdge"), widths: [12: 2.6, 16: 6.5, 18: 11], to: style))
            collectedLayers.append(addLine(
                "\(SegmentMapView.collectedLayer)-\(name)", from: source,
                color: color("Collected"), widths: [12: 1.6, 16: 4.5, 18: 8], to: style))
        }

        /// Adds a layer of segments to collect. They are dashed, like paths
        /// on a hiking map.
        @discardableResult
        private func addNotCollectedLine(_ identifier: String, from source: MLNSource, to style: MLNStyle) -> MLNStyleLayer {
            addLine(identifier, from: source, color: color("NotCollected"), widths: [12: 0.8, 16: 2, 18: 3.5],
                    dashes: [2.5, 2], opacity: 0.6, to: style)
        }

        /// Adds a line layer below the labels of the base map. Its width
        /// changes with the zoom level, and a line with dashes has no round
        /// caps. A layer of segments from tiles shows from the lowest zoom
        /// level with segments.
        @discardableResult
        private func addLine(
            _ identifier: String, from source: MLNSource, color: UIColor,
            widths: [Double: Double], dashes: [Double]? = nil, opacity: Double = 1, to style: MLNStyle
        ) -> MLNStyleLayer {
            let layer = MLNLineStyleLayer(identifier: identifier, source: source)
            if source is MLNVectorTileSource {
                layer.sourceLayerIdentifier = MapPackages.tileLayer
                layer.minimumZoomLevel = Float(MapPackages.tileZoomLevels.lowerBound)
            }
            if identifier.hasPrefix("segments") {
                segmentLayerIDs.insert(identifier)
            }
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
            return layer
        }

        /// Selects the area of the segment under the tap, or else of a
        /// segment near it, so that a thin line is easy to hit.
        @objc func selectArea(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MLNMapView, let onSelectArea else { return }
            let point = recognizer.location(in: mapView)
            let layers = segmentLayerIDs
            let features = mapView.visibleFeatures(at: point, styleLayerIdentifiers: layers)
                + mapView.visibleFeatures(
                    in: CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44),
                    styleLayerIdentifiers: layers)
            guard let area = features.lazy.compactMap({ $0.attribute(forKey: MapPackages.areaProperty) as? NSNumber }).first
            else { return }
            onSelectArea(area.intValue)
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

extension SegmentMapView {
    /// The features of the segments for the map, built off the main thread.
    /// Each feature has the ID of its segment. A cancelled task gets no
    /// features, because a newer list replaces it.
    @concurrent nonisolated static func features(of segments: [Segment]) async -> sending MLNShapeCollectionFeature {
        guard !Task.isCancelled else { return MLNShapeCollectionFeature(shapes: []) }
        return MLNShapeCollectionFeature(shapes: segments.map { segment in
            var coordinates = segment.coordinates
            let feature = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
            feature.identifier = segment.id
            return feature
        })
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
