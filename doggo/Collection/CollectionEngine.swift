//
//  CollectionEngine.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import Foundation

/// The segments that one dog has collected, and the covered parts of every
/// segment that its walks touch.
nonisolated struct DogCollection: Equatable, Sendable {
    var coveredParts: [Segment.ID: CoveredParts] = [:]
    var collected: [Segment.ID: CollectedSegment] = [:]

    var collectedSegments: Set<Segment.ID> {
        Set(collected.keys)
    }
}

/// A collected segment with what the completions need to know about it.
nonisolated struct CollectedSegment: Equatable, Sendable {
    let area: Int
    /// The street of the segment, or nil if it has no name.
    let street: Street.ID?
    let lengthMetres: Double
    /// The time of the walk point that made the covered parts reach the
    /// collected share.
    let collectedAt: Date
}

/// Matches walks against the segments of a map release and applies every
/// rule of `CollectionRules`. It has no user interface, location code,
/// storage or networking.
///
/// The collection is always calculated from the walks (ADR 0002). The engine
/// has two modes with the same rules. The rebuild mode matches all walks of
/// the dogs at once. The live mode (`LiveWalk`) takes the points of the
/// current walk one by one.
nonisolated struct CollectionEngine: Sendable {
    /// A walk as the engine sees it: its raw track and the dogs that take part.
    struct Walk<Dog: Hashable & Sendable>: Sendable {
        let dogs: Set<Dog>
        let track: Track
    }

    private let lines: [SegmentLine]
    private let grid: SegmentGrid

    init(segments: [Segment]) {
        lines = segments.map(SegmentLine.init)
        grid = SegmentGrid(lines: lines)
    }

    /// The collection of each of the dogs, from all their walks. A dog
    /// collects nothing from a walk that it did not take part in.
    func rebuild<Dog>(dogs: Set<Dog>, walks: [Walk<Dog>]) -> [Dog: DogCollection] {
        var covered = Dictionary(uniqueKeysWithValues: dogs.map { ($0, [Int: [CoveredInterval]]()) })
        for walk in walks {
            let intervals = coveredIntervals(of: walk.track)
            for dog in walk.dogs where covered[dog] != nil {
                for (line, lineIntervals) in intervals {
                    covered[dog]![line, default: []] += lineIntervals
                }
            }
        }
        return covered.mapValues(collection(from:))
    }

    /// Adds up the covered intervals of each line in the order of time, so
    /// that a collected segment gets the date of the point that collected it.
    private func collection(from covered: [Int: [CoveredInterval]]) -> DogCollection {
        var collection = DogCollection()
        for (index, intervals) in covered {
            let line = lines[index]
            var parts = CoveredParts()
            var collectedAt: Date?
            for covered in intervals.sorted(by: { $0.date < $1.date }) {
                parts.add(covered.interval)
                if collectedAt == nil, line.isCollected(by: parts) {
                    collectedAt = covered.date
                }
            }
            collection.coveredParts[line.id] = parts
            if let collectedAt {
                collection.collected[line.id] = line.collectedSegment(at: collectedAt)
            }
        }
        return collection
    }

    /// Boxes that hold every segment that the track can cover. The map
    /// packages are too big to load at once, so the app loads only the
    /// segments in these boxes before a rebuild. Stretches that cover nothing,
    /// for example a car trip after the walk, add no box.
    static func coverableBoxes(of track: Track) -> [CoordinateBox] {
        /// A box holds at most this many stretches, so that a long walk does
        /// not become one big box.
        let stretchesPerBox = 100
        var boxes: [CoordinateBox] = []
        var box: CoordinateBox?
        var stretchesInBox = 0
        var lastTo: TrackPoint?
        for (from, to) in coveringStretches(of: track) {
            if lastTo != from || stretchesInBox == stretchesPerBox {
                box.map { boxes.append($0) }
                box = nil
                stretchesInBox = 0
            }
            box = box.map { $0.including(from).including(to) } ?? CoordinateBox(from).including(to)
            stretchesInBox += 1
            lastTo = to
        }
        box.map { boxes.append($0) }
        return boxes.map { box in
            let margin = LocalPlane.degrees(
                metres: CollectionRules.coverRadiusMetres,
                atLatitude: max(abs(box.minLatitude), abs(box.maxLatitude)))
            return CoordinateBox(
                minLongitude: box.minLongitude - margin.longitude, maxLongitude: box.maxLongitude + margin.longitude,
                minLatitude: box.minLatitude - margin.latitude, maxLatitude: box.maxLatitude + margin.latitude)
        }
    }

    /// The part of a segment line that one stretch of track covers, and the
    /// time of the point at the end of the stretch.
    private struct CoveredInterval {
        let date: Date
        let interval: ClosedRange<Double>
    }

    /// The covered intervals of one track, by the index of the segment line.
    private func coveredIntervals(of track: Track) -> [Int: [CoveredInterval]] {
        var covered: [Int: [CoveredInterval]] = [:]
        for (from, to) in Self.coveringStretches(of: track) {
            for (index, intervals) in coveredIntervals(ofStretchFrom: from, to: to) {
                covered[index, default: []] += intervals.map { CoveredInterval(date: to.timestamp, interval: $0) }
            }
        }
        return covered
    }

    /// The parts of the segment lines that one stretch of track covers, by
    /// the index of the line.
    private func coveredIntervals(ofStretchFrom from: TrackPoint, to: TrackPoint) -> [Int: [ClosedRange<Double>]] {
        var covered: [Int: [ClosedRange<Double>]] = [:]
        for index in grid.lines(near: from.coordinate, to.coordinate, withinMetres: CollectionRules.coverRadiusMetres) {
            let intervals = lines[index].covered(byStretchFrom: from, to: to)
            if !intervals.isEmpty {
                covered[index] = intervals
            }
        }
        return covered
    }

    /// The stretches of the track that can cover anything.
    private static func coveringStretches(of track: Track) -> [(TrackPoint, TrackPoint)] {
        let points = track.points.filter(isAccurate)
        return zip(points, points.dropFirst()).filter { covers($0, $1) }
    }

    /// Whether a point is accurate enough to take part in matching.
    private static func isAccurate(_ point: TrackPoint) -> Bool {
        // Core Location gives a negative accuracy for a point that is not valid.
        (0...CollectionRules.worstHorizontalAccuracyMetres).contains(point.horizontalAccuracy)
    }

    /// Whether the stretch between two points is short and slow enough to
    /// cover anything.
    private static func covers(_ from: TrackPoint, _ to: TrackPoint) -> Bool {
        let seconds = to.timestamp.timeIntervalSince(from.timestamp)
        let metres = from.distance(to: to)
        guard seconds > 0, metres <= CollectionRules.longestStretchMetres else { return false }
        return metres / seconds * 3.6 <= CollectionRules.maximumSpeedKilometresPerHour
    }
}

nonisolated extension CollectionEngine {
    /// A box that holds every segment within the radius of the point, and
    /// every segment that the stretch of track that ends at the point can
    /// cover. A live walk needs the segments of this box before it adds the point.
    static func box(around point: CLLocationCoordinate2D, withinMetres radius: Double) -> CoordinateBox {
        let metres = max(radius, CollectionRules.longestStretchMetres + CollectionRules.coverRadiusMetres)
        let margin = LocalPlane.degrees(metres: metres, atLatitude: abs(point.latitude))
        return CoordinateBox(
            minLongitude: point.longitude - margin.longitude, maxLongitude: point.longitude + margin.longitude,
            minLatitude: point.latitude - margin.latitude, maxLatitude: point.latitude + margin.latitude)
    }

    /// The segments within the radius of the point that are new for at least
    /// one of the dogs: segments that its collection does not hold. A dog
    /// with no collection has collected nothing.
    func newSegments<Dog>(
        near point: CLLocationCoordinate2D, withinMetres radius: Double, for dogs: Set<Dog>,
        in collections: [Dog: DogCollection]
    ) -> [Segment] {
        grid.lines(near: point, point, withinMetres: radius).compactMap { index in
            let line = lines[index]
            guard line.distance(to: point) <= radius,
                  dogs.contains(where: { collections[$0]?.collected[line.id] == nil })
            else { return nil }
            return line.segment
        }
    }

    /// The line nearest to the point within the radius, if any.
    private func nearestLine(to point: CLLocationCoordinate2D, withinMetres radius: Double) -> SegmentLine? {
        grid.lines(near: point, point, withinMetres: radius)
            .map { (line: lines[$0], distance: lines[$0].distance(to: point)) }
            .filter { $0.distance <= radius }
            .min { $0.distance < $1.distance }?
            .line
    }

    /// The current walk in live mode. It takes the points of the walk one by
    /// one, with the same rules as the rebuild mode. After the last point,
    /// the collections are the same as a rebuild of all walks of the dogs.
    struct LiveWalk<Dog: Hashable & Sendable>: Sendable {
        /// The dogs that take part in the walk.
        let dogs: Set<Dog>
        /// The collection of each dog on the walk, from its other walks and
        /// the points of this walk so far.
        private(set) var collections: [Dog: DogCollection]
        /// The area that the walker is in: the area of the segment nearest to
        /// the last point. It stays the same while no segment is near, and
        /// it is nil before the walker first comes near a segment.
        private(set) var currentArea: Area.ID?
        /// The last point that was accurate enough to take part in matching.
        private var lastPoint: TrackPoint?

        /// Starts a live walk on the collections of the dogs from their other
        /// walks. A dog with no collection starts with an empty one.
        init(dogs: Set<Dog>, collections: [Dog: DogCollection]) {
            self.dogs = dogs
            self.collections = Dictionary(uniqueKeysWithValues: dogs.map { ($0, collections[$0] ?? DogCollection()) })
        }

        /// Adds the next point of the walk. The engine must hold the segments
        /// in `CollectionEngine.box(around:withinMetres:)` of the point. It returns the segments that became collected with
        /// this point, for each dog on the walk. A dog with no new segment
        /// has no entry.
        mutating func add(_ point: TrackPoint, using engine: CollectionEngine) -> [Dog: Set<Segment.ID>] {
            guard CollectionEngine.isAccurate(point) else { return [:] }
            if let line = engine.nearestLine(to: point.coordinate, withinMetres: CollectionRules.currentAreaRadiusMetres) {
                currentArea = line.area
            }
            defer { lastPoint = point }
            guard let lastPoint, CollectionEngine.covers(lastPoint, point) else { return [:] }
            var newlyCollected: [Dog: Set<Segment.ID>] = [:]
            for (index, intervals) in engine.coveredIntervals(ofStretchFrom: lastPoint, to: point) {
                let line = engine.lines[index]
                for dog in dogs where Self.add(intervals, of: line, at: point.timestamp, to: &collections[dog, default: DogCollection()]) {
                    newlyCollected[dog, default: []].insert(line.id)
                }
            }
            return newlyCollected
        }

        /// Adds the covered intervals of a line to the collection, in place,
        /// so that a big collection is not copied for every point. It returns
        /// whether the segment became collected.
        private static func add(
            _ intervals: [ClosedRange<Double>], of line: SegmentLine, at date: Date, to collection: inout DogCollection
        ) -> Bool {
            intervals.forEach { collection.coveredParts[line.id, default: CoveredParts()].add($0) }
            guard collection.collected[line.id] == nil, line.isCollected(by: collection.coveredParts[line.id]!)
            else { return false }
            collection.collected[line.id] = line.collectedSegment(at: date)
            return true
        }
    }
}

/// A flat plane in metres around one point. Across the size of a segment the
/// error of this projection is far below the accuracy of GPS.
nonisolated private struct LocalPlane: Sendable {
    static let metresPerDegreeLatitude = 6_371_008.8 * Double.pi / 180

    let latitude: Double
    let longitude: Double
    let metresPerDegreeLongitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        metresPerDegreeLongitude = Self.metresPerDegreeLatitude * cos(latitude * .pi / 180)
    }

    /// A distance in metres as degrees of latitude and of longitude.
    static func degrees(metres: Double, atLatitude latitude: Double) -> (latitude: Double, longitude: Double) {
        (metres / metresPerDegreeLatitude,
         metres / LocalPlane(latitude: latitude, longitude: 0).metresPerDegreeLongitude)
    }

    func point(latitude: Double, longitude: Double) -> SIMD2<Double> {
        SIMD2((longitude - self.longitude) * metresPerDegreeLongitude,
              (latitude - self.latitude) * Self.metresPerDegreeLatitude)
    }
}

/// A segment on its own local plane, ready for matching.
nonisolated private struct SegmentLine: Sendable {
    let segment: Segment
    let plane: LocalPlane
    let points: [SIMD2<Double>]
    /// The distance of each point from the start of the line, in metres.
    let distances: [Double]
    let minLatitude, maxLatitude, minLongitude, maxLongitude: Double

    var id: Segment.ID { segment.id }
    var area: Int { segment.area }

    /// The length on the local plane. The covered parts use the same plane,
    /// so the collected share compares like with like.
    var length: Double { distances.last ?? 0 }

    /// Whether the covered parts reach the collected share of this line.
    func isCollected(by parts: CoveredParts) -> Bool {
        parts.length >= CollectionRules.collectedShare * length
    }

    /// This segment as collected at the date. Completions add up the length
    /// that the map package gives.
    func collectedSegment(at date: Date) -> CollectedSegment {
        CollectedSegment(area: segment.area, street: segment.streetID, lengthMetres: segment.lengthMetres,
                         collectedAt: date)
    }

    init(_ segment: Segment) {
        self.segment = segment
        let first = segment.coordinates.first ?? CLLocationCoordinate2D()
        plane = LocalPlane(latitude: first.latitude, longitude: first.longitude)
        var points: [SIMD2<Double>] = []
        for coordinate in segment.coordinates {
            let point = plane.point(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if point != points.last { points.append(point) }
        }
        self.points = points
        var distances = [0.0]
        for (a, b) in zip(points, points.dropFirst()) {
            distances.append(distances[distances.count - 1] + (b - a).length)
        }
        self.distances = distances
        minLatitude = segment.coordinates.map(\.latitude).min() ?? 0
        maxLatitude = segment.coordinates.map(\.latitude).max() ?? 0
        minLongitude = segment.coordinates.map(\.longitude).min() ?? 0
        maxLongitude = segment.coordinates.map(\.longitude).max() ?? 0
    }

    /// The shortest distance from the point to this line, in metres.
    func distance(to coordinate: CLLocationCoordinate2D) -> Double {
        let point = plane.point(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard points.count > 1 else { return points.first.map { ($0 - point).length } ?? .infinity }
        return points.indices.dropLast().map { index in
            let start = points[index]
            let leg = points[index + 1] - start
            let t = min(max(((point - start) * leg).sum() / (leg * leg).sum(), 0), 1)
            return (start + t * leg - point).length
        }.min()!
    }

    /// The parts of this line within the cover radius of the stretch between
    /// two track points, in metres from the start of the line.
    func covered(byStretchFrom from: TrackPoint, to: TrackPoint) -> [ClosedRange<Double>] {
        let a = plane.point(latitude: from.latitude, longitude: from.longitude)
        let b = plane.point(latitude: to.latitude, longitude: to.longitude)
        var intervals: [ClosedRange<Double>] = []
        for index in points.indices.dropLast() {
            let start = points[index]
            let leg = points[index + 1] - start
            guard let t = Self.range(from: start, along: leg, withinRadius: CollectionRules.coverRadiusMetres,
                                     ofStretchFrom: a, to: b)
            else { continue }
            let legLength = distances[index + 1] - distances[index]
            intervals.append((distances[index] + t.lowerBound * legLength)...(distances[index] + t.upperBound * legLength))
        }
        return intervals
    }

    /// The range of t in 0...1 for which `start + t * leg` lies within the
    /// radius of the stretch from a to b. A leg is the straight line between
    /// two consecutive points of the segment.
    ///
    /// The points within the radius of a stretch form a capsule: a rectangle
    /// along the stretch with a disc at each end. The capsule is convex, so
    /// the leg meets it in one range, which spans the ranges of its parts.
    static func range(
        from start: SIMD2<Double>, along leg: SIMD2<Double>, withinRadius radius: Double,
        ofStretchFrom a: SIMD2<Double>, to b: SIMD2<Double>
    ) -> ClosedRange<Double>? {
        let parts = [
            disc(around: a, radius: radius, start: start, leg: leg),
            disc(around: b, radius: radius, start: start, leg: leg),
            rectangle(from: a, to: b, radius: radius, start: start, leg: leg),
        ].compactMap { $0 }
        guard let low = parts.map(\.lowerBound).min(), let high = parts.map(\.upperBound).max() else { return nil }
        let clamped = (max(low, 0), min(high, 1))
        return clamped.0 <= clamped.1 ? clamped.0...clamped.1 : nil
    }

    private static func disc(
        around centre: SIMD2<Double>, radius: Double, start: SIMD2<Double>, leg: SIMD2<Double>
    ) -> ClosedRange<Double>? {
        let offset = start - centre
        let a = (leg * leg).sum()
        let b = 2 * (leg * offset).sum()
        let c = (offset * offset).sum() - radius * radius
        let discriminant = b * b - 4 * a * c
        guard a > 0, discriminant >= 0 else { return nil }
        let root = discriminant.squareRoot()
        return ((-b - root) / (2 * a))...((-b + root) / (2 * a))
    }

    private static func rectangle(
        from a: SIMD2<Double>, to b: SIMD2<Double>, radius: Double, start: SIMD2<Double>, leg: SIMD2<Double>
    ) -> ClosedRange<Double>? {
        let stretch = b - a
        let stretchLength = stretch.length
        guard stretchLength > 0 else { return nil }
        let direction = stretch / stretchLength
        let normal = SIMD2(-direction.y, direction.x)
        let offset = start - a
        var range: ClosedRange<Double>? = -Double.infinity...Double.infinity
        range = clip(range, value: (offset * direction).sum(), change: (leg * direction).sum(),
                     between: 0, and: stretchLength)
        range = clip(range, value: (offset * normal).sum(), change: (leg * normal).sum(),
                     between: -radius, and: radius)
        return range
    }

    /// Narrows a range of t to where `value + t * change` lies between two limits.
    private static func clip(
        _ range: ClosedRange<Double>?, value: Double, change: Double, between low: Double, and high: Double
    ) -> ClosedRange<Double>? {
        guard let range else { return nil }
        if change == 0 {
            return (low...high).contains(value) ? range : nil
        }
        let t1 = (low - value) / change, t2 = (high - value) / change
        let lower = max(range.lowerBound, min(t1, t2)), upper = min(range.upperBound, max(t1, t2))
        return lower <= upper ? lower...upper : nil
    }
}

/// Finds the segment lines near a stretch of track quickly, with a grid of
/// cells in degrees.
nonisolated private struct SegmentGrid: Sendable {
    private struct Cell: Hashable, Sendable {
        let x: Int
        let y: Int
    }

    /// About 550 m north to south and 380 m west to east in Switzerland.
    private static let cellDegrees = 0.005

    private let lines: [SegmentLine]
    private var cells: [Cell: [Int]] = [:]

    init(lines: [SegmentLine]) {
        self.lines = lines
        for (index, line) in lines.enumerated() {
            for cell in Self.cells(latitudes: line.minLatitude...line.maxLatitude,
                                   longitudes: line.minLongitude...line.maxLongitude) {
                cells[cell, default: []].append(index)
            }
        }
    }

    /// The indices of the lines whose box lies within the radius of the box
    /// of the stretch between two points.
    func lines(near from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D, withinMetres radius: Double) -> Set<Int> {
        let margin = LocalPlane.degrees(metres: radius, atLatitude: max(abs(from.latitude), abs(to.latitude)))
        let latitudes = (min(from.latitude, to.latitude) - margin.latitude)...(max(from.latitude, to.latitude) + margin.latitude)
        let longitudes = (min(from.longitude, to.longitude) - margin.longitude)...(max(from.longitude, to.longitude) + margin.longitude)
        var result = Set<Int>()
        for cell in Self.cells(latitudes: latitudes, longitudes: longitudes) {
            for index in cells[cell] ?? [] {
                let line = lines[index]
                if line.maxLatitude >= latitudes.lowerBound, line.minLatitude <= latitudes.upperBound,
                   line.maxLongitude >= longitudes.lowerBound, line.minLongitude <= longitudes.upperBound {
                    result.insert(index)
                }
            }
        }
        return result
    }

    private static func cells(latitudes: ClosedRange<Double>, longitudes: ClosedRange<Double>) -> [Cell] {
        func cell(_ degrees: Double) -> Int { Int((degrees / cellDegrees).rounded(.down)) }
        return (cell(longitudes.lowerBound)...cell(longitudes.upperBound)).flatMap { x in
            (cell(latitudes.lowerBound)...cell(latitudes.upperBound)).map { y in Cell(x: x, y: y) }
        }
    }
}

nonisolated private extension SIMD2<Double> {
    var length: Double { (self * self).sum().squareRoot() }
}

nonisolated private extension CoordinateBox {
    init(_ point: TrackPoint) {
        self.init(minLongitude: point.longitude, maxLongitude: point.longitude,
                  minLatitude: point.latitude, maxLatitude: point.latitude)
    }

    func including(_ point: TrackPoint) -> CoordinateBox {
        CoordinateBox(
            minLongitude: min(minLongitude, point.longitude), maxLongitude: max(maxLongitude, point.longitude),
            minLatitude: min(minLatitude, point.latitude), maxLatitude: max(maxLatitude, point.latitude))
    }
}
