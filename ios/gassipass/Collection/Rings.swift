//
//  Rings.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import CoreLocation
import Foundation

/// The place that a pack calls home, which is the centre of its rings.
///
/// The centre has six decimals, about 10 cm, so that the centre of a ring
/// stamp is the same value on every phone and on the server.
nonisolated struct HomeBase: Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    /// The home base at the coordinates, rounded to six decimals.
    init(latitude: Double, longitude: Double) {
        self.latitude = (latitude * 1e6).rounded() / 1e6
        self.longitude = (longitude * 1e6).rounded() / 1e6
    }

    /// The home base at the coordinate, rounded to six decimals.
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// The home base as a coordinate for the map.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Starts within this distance of each other count as one place.
    static let proposalPlaceRadiusMetres = 100.0

    /// The home base that the app proposes from the starts of the walks of
    /// the pack, or nil without walks: the place where most walks start.
    /// With one walk, that is the start of the walk. The place is the start
    /// with the most other starts within 100 m, and the earlier start of two
    /// such places. The proposal is the middle of the starts of that place.
    static func proposal(fromStarts starts: [CLLocationCoordinate2D]) -> HomeBase? {
        guard let first = starts.first else { return nil }
        let plane = LocalPlane(latitude: first.latitude, longitude: first.longitude)
        let points = starts.map { plane.point(latitude: $0.latitude, longitude: $0.longitude) }
        var best: [Int] = []
        for point in points {
            let place = points.indices.filter { (points[$0] - point).length <= proposalPlaceRadiusMetres }
            if place.count > best.count {
                best = place
            }
        }
        let count = Double(best.count)
        return HomeBase(
            latitude: best.reduce(0) { $0 + starts[$1].latitude } / count,
            longitude: best.reduce(0) { $0 + starts[$1].longitude } / count)
    }
}

/// All segments within a straight-line distance of a home base. A segment
/// belongs to a ring when its midpoint lies within the radius.
nonisolated struct Ring: Hashable, Sendable {
    /// The number of the ring, from 1.
    let number: Int
    let centre: HomeBase

    /// Ring 1 has a radius of 250 m, and each next ring has a radius about
    /// 1.4 times as large: 250, 350, 500, 700, 1000 m and so on, doubling
    /// every second ring.
    var radiusMetres: Double {
        Self.radiusMetres(of: number)
    }

    /// The radius of the ring with the number, in metres.
    static func radiusMetres(of number: Int) -> Double {
        let base = number % 2 == 1 ? 250.0 : 350.0
        return base * pow(2, Double((number - 1) / 2))
    }

    /// The next ring around the same home base.
    var next: Ring {
        Ring(number: number + 1, centre: centre)
    }

    /// The name of the ring, for example "Ring 3".
    var name: String {
        String(localized: "Ring \(number)")
    }
}

/// What a ring needs to know about a segment.
nonisolated struct RingSegment: Equatable, Sendable {
    let id: Segment.ID
    /// The feature ID of the segment in the map tiles.
    let fid: Int
    /// The BFS number of the area of the segment.
    let area: Int
    /// The street of the segment, or nil if it has no name.
    let street: Street.ID?
    let lengthMetres: Double
    /// The straight-line distance from the home base to the midpoint of the
    /// segment, which decides the rings of the segment.
    let distanceMetres: Double
    /// The straight-line distance from the home base to the nearest point
    /// of the segment, which the ring card shows.
    let nearestDistanceMetres: Double
}

/// The segments of the map packages whose midpoints lie within a radius of
/// a home base, the nearest first. They give the completion of each ring
/// within the radius.
nonisolated struct RingSegments: Sendable {
    let centre: HomeBase
    /// Every segment whose midpoint lies within this radius is here.
    let radiusMetres: Double
    let segments: [RingSegment]

    /// - Parameter segments: The segments of the map packages around the
    ///   home base. Those whose midpoint lies farther away than the radius
    ///   are left out.
    init(centre: HomeBase, segments: [Segment], radiusMetres: Double) {
        self.centre = centre
        self.radiusMetres = radiusMetres
        let plane = LocalPlane(latitude: centre.latitude, longitude: centre.longitude)
        self.segments = segments
            .map { segment in
                let points = segment.coordinates.map { plane.point(latitude: $0.latitude, longitude: $0.longitude) }
                return RingSegment(
                    id: segment.id, fid: segment.fid, area: segment.area, street: segment.streetID,
                    lengthMetres: segment.lengthMetres,
                    distanceMetres: Self.midpoint(of: points).length,
                    nearestDistanceMetres: Self.distanceToCentre(of: points))
            }
            .filter { $0.distanceMetres <= radiusMetres }
            .sorted { ($0.distanceMetres, $0.id) < ($1.distanceMetres, $1.id) }
    }

    /// The box that holds every segment whose midpoint lies within the
    /// radius of the home base.
    static func box(around centre: HomeBase, withinMetres radius: Double) -> CoordinateBox {
        let margin = LocalPlane.degrees(metres: radius, atLatitude: abs(centre.latitude))
        return CoordinateBox(
            minLongitude: centre.longitude - margin.longitude, maxLongitude: centre.longitude + margin.longitude,
            minLatitude: centre.latitude - margin.latitude, maxLatitude: centre.latitude + margin.latitude)
    }

    /// Whether the segments of the ring are all here.
    func holds(_ ring: Ring) -> Bool {
        ring.centre == centre && ring.radiusMetres <= radiusMetres
    }

    /// The rings whose segments are all here, from ring 1.
    var heldRings: [Ring] {
        var rings: [Ring] = []
        var ring = Ring(number: 1, centre: centre)
        while holds(ring) {
            rings.append(ring)
            ring = ring.next
        }
        return rings
    }

    /// The segments of the ring, the nearest first. The ring must be one
    /// that these segments hold.
    func segments(of ring: Ring) -> ArraySlice<RingSegment> {
        let radius = ring.radiusMetres
        let end = segments.firstIndex { $0.distanceMetres > radius } ?? segments.endIndex
        return segments[..<end]
    }

    /// The completion of the ring for the dog with the collection.
    func completion(of ring: Ring, for collection: DogCollection) -> Completion {
        totals(of: ring).completion(with: collected(in: ring, by: collection))
    }

    /// The date on which the dog completed the ring: the `collectedAt` of
    /// the segment whose collection first lifted the completion to 95%. It
    /// is nil when the dog has not completed the ring.
    func completedDate(of ring: Ring, for collection: DogCollection) -> Date? {
        let totals = totals(of: ring)
        return totals.firstDate(of: collected(in: ring, by: collection), where: Self.isCompleted)
    }

    /// The segments that the dog has not collected, the nearest to the home
    /// base first by their nearest point, at most the count.
    func nearestNewSegments(for collection: DogCollection, count: Int) -> [RingSegment] {
        Array(segments
            .filter { collection.collected[$0.id] == nil }
            .sorted { ($0.nearestDistanceMetres, $0.id) < ($1.nearestDistanceMetres, $1.id) }
            .prefix(count))
    }

    /// Whether a dog with the completion has completed a ring. A ring is
    /// completed by the rule of an area, and a ring without segments is not.
    static func isCompleted(_ completion: Completion) -> Bool {
        completion.segmentCount > 0 && StampStep.completed.isReached(by: completion)
    }

    /// Whether the ring holds no segment while a ring beyond it does. Such a
    /// ring can never be completed, so it is not a current ring. Around a
    /// home base without any segment, for example outside the map packages,
    /// no ring is skipped, so that the app does not load ring after ring.
    func isSkipped(_ ring: Ring) -> Bool {
        holds(ring) && !segments.isEmpty && segments(of: ring).isEmpty
    }

    private func totals(of ring: Ring) -> Totals {
        let segments = segments(of: ring)
        return Totals(segmentCount: segments.count, lengthMetres: segments.reduce(0) { $0 + $1.lengthMetres })
    }

    private func collected(in ring: Ring, by collection: DogCollection) -> [CollectedSegment] {
        segments(of: ring).compactMap { collection.collected[$0.id] }
    }

    /// The point halfway along the points of a segment on the plane.
    private static func midpoint(of points: [SIMD2<Double>]) -> SIMD2<Double> {
        guard let first = points.first else { return SIMD2(Double.infinity, Double.infinity) }
        let legs: [(start: SIMD2<Double>, vector: SIMD2<Double>)] = zip(points, points.dropFirst()).map { ($0, $1 - $0) }
        var remaining = legs.reduce(0.0) { $0 + $1.vector.length } / 2
        for leg in legs {
            let length = leg.vector.length
            guard length > 0 else { continue }
            if remaining <= length {
                return leg.start + leg.vector * (remaining / length)
            }
            remaining -= length
        }
        return first
    }

    /// The shortest distance from the centre of the plane to the line
    /// through the points of a segment.
    private static func distanceToCentre(of points: [SIMD2<Double>]) -> Double {
        guard points.count > 1 else { return points.first?.length ?? .infinity }
        return zip(points, points.dropFirst()).map { start, end in
            let leg = end - start
            let squared = (leg * leg).sum()
            let t = squared > 0 ? min(max(-(start * leg).sum() / squared, 0), 1) : 0
            return (start + leg * t).length
        }.min() ?? .infinity
    }

    private struct Totals: CompletionTotals {
        let segmentCount: Int
        let lengthMetres: Double
    }
}

nonisolated extension CollectionEngine {
    /// A new record for each dog and ring that has no record yet and that
    /// the dog has completed, sorted by date. Only the rings that the
    /// segments hold count. The date of a record is the date of the segment
    /// whose collection completed the ring. The existing records stay.
    static func ringRecords<Dog>(
        collections: [Dog: DogCollection], around rings: RingSegments, existing: [CompletedRecord<Dog, Ring>]
    ) -> [CompletedRecord<Dog, Ring>] {
        let recorded = Set(existing.map { DogRing(dog: $0.dog, ring: $0.goal) })
        var new: [CompletedRecord<Dog, Ring>] = []
        let held = rings.heldRings
        for (dog, collection) in collections {
            for ring in held where !recorded.contains(DogRing(dog: dog, ring: ring)) {
                if let date = rings.completedDate(of: ring, for: collection) {
                    new.append(CompletedRecord(dog: dog, goal: ring, date: date))
                }
            }
        }
        return new.sorted { ($0.date, $0.goal.number) < ($1.date, $1.goal.number) }
    }

    /// The rings that the newly collected segments completed, with the dogs
    /// that completed each one. Like `completedGoals`, it does not know the
    /// records.
    static func completedRings<Dog>(
        by newlyCollected: [Dog: Set<Segment.ID>], in collections: [Dog: DogCollection], around rings: RingSegments
    ) -> [Ring: Set<Dog>] {
        var completed: [Ring: Set<Dog>] = [:]
        for (dog, segments) in newlyCollected {
            guard let after = collections[dog] else { continue }
            var before = after
            segments.forEach { before.collected[$0] = nil }
            for ring in rings.heldRings
            where RingSegments.isCompleted(rings.completion(of: ring, for: after))
                && !RingSegments.isCompleted(rings.completion(of: ring, for: before)) {
                completed[ring, default: []].insert(dog)
            }
        }
        return completed
    }

    /// The current ring of the dog around the home base: the ring after the
    /// highest ring stamp of the dog around it, or ring 1. A ring below a
    /// ring stamp that the dog has not completed, for example because of
    /// private ways, is not the current ring, so it never keeps the dog
    /// back. With the segments around the home base, the current ring also
    /// passes over the rings that they skip (`RingSegments.isSkipped`).
    static func currentRing<Dog>(
        of dog: Dog, around centre: HomeBase, records: [CompletedRecord<Dog, Ring>],
        skippingEmptyIn rings: RingSegments? = nil
    ) -> Ring {
        let highest = records.filter { $0.dog == dog && $0.goal.centre == centre }.map(\.goal.number).max() ?? 0
        var ring = Ring(number: highest + 1, centre: centre)
        while rings?.isSkipped(ring) == true {
            ring = ring.next
        }
        return ring
    }

    private struct DogRing<Dog: Hashable>: Hashable {
        let dog: Dog
        let ring: Ring
    }
}
