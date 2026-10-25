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
/// above them. The map frames the track if there is one, or else the ring if
/// `framesRing` is set. Otherwise it starts at `centre`, or follows the
/// walker's location. With `onSelectArea`, a tap on a segment selects the
/// area that the segment lies in, and `onMoveCentre` gets the centre of the
/// map after each move.
///
/// The map draws the segments from the vector tiles of the map packages,
/// and none when it is zoomed out far. MapLibre loads, caches and draws only
/// the tiles that it needs. The collected segments are a filter on the
/// feature IDs of the tiles, so a new collection changes only the filter.
/// Every collected segment shows in the full collected colour. Below it,
/// each shade of the marks has its own layer and filter, a halo of the
/// collected colour that is stronger the more often the dogs walked there.
/// The highlighted segments, for example the nearest new segments, are a
/// filter in the same way. With `shownSegments`, the map shows only those
/// segments as not collected, and the collected segments of the tiles.
/// Their features build off the main thread. With `ring`, the map draws the
/// ring as a circle.
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
    static let markLayer = "segments-mark"

    /// Where the map starts without a track when the system knows no last
    /// location, or when the walker does not share it: Dietikon, the first
    /// test area.
    static let startCenter = CLLocationCoordinate2D(latitude: 47.4035, longitude: 8.4000)
    static let startZoomLevel = 14.0

    var shownSegments: [Segment]?
    var track: [CLLocationCoordinate2D] = []
    /// The feature IDs of the collected segments (`Segment.fid`), with the
    /// shades of their marks.
    var markedFeatures = MarkedFeatures()
    /// The feature IDs of the segments that the map shows in a stronger
    /// style than the other segments that are not collected.
    var highlightedFeatures: Set<Int> = []
    /// The ring that the map draws as a circle, if any.
    var ring: Ring?
    /// Whether the map frames the ring at the start.
    var framesRing = false
    /// Where the map starts without a track, or nil to follow the walker.
    var centre: CLLocationCoordinate2D?
    /// The zoom level at the start, when the map follows the walker or
    /// starts at the centre.
    var zoomLevel = startZoomLevel
    /// Gets the BFS number of the area of a tapped segment.
    var onSelectArea: ((Int) -> Void)?
    /// Gets the centre of the map after each move.
    var onMoveCentre: ((CLLocationCoordinate2D) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            shownSegments: shownSegments, track: track, markedFeatures: markedFeatures,
            highlightedFeatures: highlightedFeatures, ring: ring)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let isDark = context.environment.colorScheme == .dark
        // The light base map starts to load at once. The dark style loads
        // from JSON below, so it starts on the small bundled style.
        let mapView = FramingMapView(frame: .zero, styleURL: isDark ? Self.offlineStyle : Self.baseMapStyle)
        if !track.isEmpty {
            mapView.boundsToFrame = Self.bounds(of: track)
        } else if framesRing, let ring {
            mapView.boundsToFrame = Self.bounds(of: Self.circle(of: ring))
            mapView.showsUserLocation = true
        } else if let centre {
            mapView.setCenter(centre, zoomLevel: zoomLevel, animated: false)
            mapView.showsUserLocation = true
        } else {
            // The last location that the system knows is near the walker, so
            // the map does not jump from the start centre to the first fix.
            let lastLocation = CLLocationManager().location?.coordinate
            mapView.setCenter(lastLocation ?? Self.startCenter, zoomLevel: zoomLevel, animated: false)
            mapView.showsUserLocation = true
            // The map stops following when the walker moves the map.
            mapView.userTrackingMode = .follow
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
        context.coordinator.onMoveCentre = onMoveCentre
        context.coordinator.showStyle(isDark: context.environment.colorScheme == .dark, on: mapView)
        context.coordinator.show(
            markedFeatures: markedFeatures, highlightedFeatures: highlightedFeatures,
            shownSegments: shownSegments)
        context.coordinator.show(ring: ring)
    }

    /// The points of the circle of the ring, closed.
    static func circle(of ring: Ring) -> [CLLocationCoordinate2D] {
        let centre = ring.centre
        let degrees = LocalPlane.degrees(metres: ring.radiusMetres, atLatitude: abs(centre.latitude))
        let count = 120
        return (0...count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi
            return CLLocationCoordinate2D(
                latitude: centre.latitude + degrees.latitude * sin(angle),
                longitude: centre.longitude + degrees.longitude * cos(angle))
        }
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
        private var markedFeatures: MarkedFeatures
        private var highlightedFeatures: Set<Int>
        private var ring: Ring?
        /// The source of `shownSegments`, or nil if the map shows the tiles.
        private var segmentSource: MLNShapeSource?
        /// The source of the circle of the ring, or nil before the style loads.
        private var ringSource: MLNShapeSource?
        /// The layers of the tiles that show the collected segments, the
        /// layers that show the halo of each shade of the marks, the layers
        /// that show the other segments, and the layers that show the
        /// highlighted segments.
        private var collectedLayers: [MLNStyleLayer] = []
        private var markLayers: [[MLNStyleLayer]] = Array(repeating: [], count: MarkedFeatures.shadeCount)
        private var notCollectedLayers: [MLNStyleLayer] = []
        private var highlightedLayers: [MLNStyleLayer] = []
        /// All layers of segments, for a tap on the map.
        private var segmentLayerIDs: Set<String> = []
        /// The update of the source that runs, if any. A newer update cancels it.
        private var update: Task<Void, Never>?
        var onSelectArea: ((Int) -> Void)?
        var onMoveCentre: ((CLLocationCoordinate2D) -> Void)?
        /// Whether the map shows the dark style, or nil before the first style.
        private var isDark: Bool?
        private var isShowingOfflineStyle = false
        /// The dark style that the map shows, or nil if it shows another style.
        private var shownDarkStyle: String?

        /// The dark style of the last download.
        private static var darkStyle = DarkMapStyle.stored()
        /// The download of the dark style, once for each launch of the app.
        private static var darkStyleDownload: Task<String?, Never>?

        init(
            shownSegments: [Segment]?, track: [CLLocationCoordinate2D], markedFeatures: MarkedFeatures,
            highlightedFeatures: Set<Int>, ring: Ring?
        ) {
            self.shownSegments = shownSegments
            self.track = track
            self.markedFeatures = markedFeatures
            self.highlightedFeatures = highlightedFeatures
            self.ring = ring
        }

        func show(markedFeatures: MarkedFeatures, highlightedFeatures: Set<Int>, shownSegments: [Segment]?) {
            if let shownSegments, shownSegments.map(\.id) != self.shownSegments?.map(\.id) {
                self.shownSegments = shownSegments
                if segmentSource != nil {
                    showSegments(shownSegments)
                }
            }
            guard markedFeatures != self.markedFeatures || highlightedFeatures != self.highlightedFeatures
            else { return }
            self.markedFeatures = markedFeatures
            self.highlightedFeatures = highlightedFeatures
            filterCollected()
        }

        func show(ring: Ring?) {
            guard ring != self.ring else { return }
            self.ring = ring
            ringSource?.shape = Self.shape(of: ring)
        }

        /// The circle of the ring, or nothing.
        private static func shape(of ring: Ring?) -> MLNShape? {
            guard let ring else { return nil }
            var coordinates = SegmentMapView.circle(of: ring)
            return MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
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

        /// Sets the filters of the layers of the tiles to the collected and
        /// the highlighted segments of now.
        private func filterCollected() {
            // A filter on an empty list is not valid, and no segment has the fid 0.
            func list(_ features: Set<Int>) -> [Int] { features.isEmpty ? [0] : Array(features) }
            let collected = NSPredicate(format: "$featureIdentifier IN %@", list(markedFeatures.all))
            collectedLayers.forEach { ($0 as? MLNVectorStyleLayer)?.predicate = collected }
            for (shade, layers) in zip(markedFeatures.shades, markLayers) {
                let marked = NSPredicate(format: "$featureIdentifier IN %@", list(shade))
                layers.forEach { ($0 as? MLNVectorStyleLayer)?.predicate = marked }
            }
            let notCollected = NSPredicate(format: "NOT ($featureIdentifier IN %@)", list(markedFeatures.all))
            notCollectedLayers.forEach { ($0 as? MLNVectorStyleLayer)?.predicate = notCollected }
            let highlighted = NSPredicate(format: "$featureIdentifier IN %@", list(highlightedFeatures))
            highlightedLayers.forEach { ($0 as? MLNVectorStyleLayer)?.predicate = highlighted }
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
            ringSource = nil
            collectedLayers = []
            markLayers = Array(repeating: [], count: MarkedFeatures.shadeCount)
            notCollectedLayers = []
            highlightedLayers = []
            segmentLayerIDs = []
            for source in MapPackages.bundled.tileSources {
                addTiles(of: source, showsNotCollected: shownSegments == nil, to: style)
            }
            filterCollected()
            if let shownSegments {
                let source = MLNShapeSource(identifier: "segments", shape: nil, options: nil)
                style.addSource(source)
                segmentSource = source
                addNotCollectedLine(SegmentMapView.notCollectedLayer, from: source, to: style)
                showSegments(shownSegments)
            }
            let ringSource = MLNShapeSource(identifier: "ring", shape: Self.shape(of: ring), options: nil)
            style.addSource(ringSource)
            self.ringSource = ringSource
            // The ring is solid, so that it differs from the dashed segments
            // that are not collected.
            addLine("ring", from: ringSource, color: color("Forest"), widths: [12: 2, 16: 3, 18: 4],
                    opacity: 0.7, to: style)
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
        /// segments that are not collected unless the map shows other
        /// segments, the layers for the collected segments and the halos of
        /// their marks, and a layer for the highlighted segments. The
        /// filters of the layers come from `filterCollected()`.
        private func addTiles(of tiles: MapPackages.TileSource, showsNotCollected: Bool, to style: MLNStyle) {
            let name = tiles.name
            let source = MLNVectorTileSource(identifier: "segments-\(name)", configurationURL: tiles.url)
            style.addSource(source)
            if showsNotCollected {
                notCollectedLayers.append(
                    addNotCollectedLine("\(SegmentMapView.notCollectedLayer)-\(name)", from: source, to: style))
                // The highlighted segments are solid and wider than the
                // other segments that are not collected.
                highlightedLayers.append(addLine(
                    "segments-highlighted-\(name)", from: source, color: color("NotCollected"),
                    widths: [12: 2, 16: 4, 18: 6], to: style))
            }
            // The halos of the marks lie below the collected segments, and a
            // segment walked more often has a stronger halo.
            for (shade, (opacity, scale)) in zip(Self.markOpacities, Self.markWidthScales).enumerated() {
                let halo = addLine(
                    "\(SegmentMapView.markLayer)-\(shade)-\(name)", from: source, color: color("Collected"),
                    widths: [12: 5 * scale, 16: 13 * scale, 18: 22 * scale], opacity: opacity, to: style)
                halo.lineBlur = NSExpression(
                    forMLNInterpolating: .zoomLevelVariable, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [12: 2, 16: 6, 18: 10]))
                markLayers[shade].append(halo)
            }
            // Collected segments are solid, with a dark edge that keeps the
            // apricot visible on the light base map.
            collectedLayers.append(addLine(
                "\(SegmentMapView.collectedEdgeLayer)-\(name)", from: source,
                color: color("CollectedEdge"), widths: [12: 2.6, 16: 6.5, 18: 11], to: style))
            collectedLayers.append(addLine(
                "\(SegmentMapView.collectedLayer)-\(name)", from: source,
                color: color("Collected"), widths: [12: 1.6, 16: 4.5, 18: 8], to: style))
        }

        /// The opacity and the width of the halo of each shade of the marks,
        /// from marked once to marked often.
        private static let markOpacities = [0.15, 0.35, 0.65]
        private static let markWidthScales = [0.8, 1.1, 1.5]

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
        ) -> MLNLineStyleLayer {
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

        /// A map that follows the walker reports no centre before it knows
        /// the location, because until then it shows the start of the map.
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            guard mapView.userTrackingMode != .follow || mapView.userLocation?.location != nil else { return }
            onMoveCentre?(mapView.centerCoordinate)
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
