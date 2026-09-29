//
//  DemoData.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

#if DEBUG
import CoreLocation
import Foundation
import SwiftData

/// Sample dogs, walks and pins in Dietikon, for screenshots and design work.
/// The app uses them when it launches with `-demoData YES`. It then keeps
/// its store in memory, so the demo never touches the real walks.
enum DemoData {
    /// Whether the app launched with `-demoData YES`.
    static var isOn: Bool {
        UserDefaults.standard.bool(forKey: "demoData")
    }

    /// Dietikon, the first test area.
    private static let dietikon = 243
    private static let schlieren = 247
    /// A small area, which Bello has completed.
    private static let huettikon = 87
    private static let station = CLLocationCoordinate2D(latitude: 47.4045, longitude: 8.4003)
    private static let park = CLLocationCoordinate2D(latitude: 47.3985, longitude: 8.3925)

    /// Inserts two dogs, a retired dog, four walks in Dietikon, a walk that
    /// completes Hüttikon and three pinned areas. It inserts nothing if the
    /// map packages do not hold Dietikon.
    static func insert(into context: ModelContext) {
        guard let shape = try? MapPackages.bundled.shape(of: dietikon) else { return }
        let luna = Dog(name: "Luna")
        let bello = Dog(name: "Bello")
        let rex = Dog(name: "Rex")
        luna.coatColour = .black
        rex.coatColour = .grey
        context.insert(luna)
        context.insert(bello)
        context.insert(rex)

        let aroundStation = segments(of: shape, near: station, withinMetres: 450)
        let aroundPark = segments(of: shape, near: park, withinMetres: 350)
        let day: TimeInterval = 86_400
        addWalk(along: aroundStation, dogs: [luna, bello], startedAt: .now - 3 * day, to: context)
        addWalk(along: aroundPark, dogs: [luna], startedAt: .now - day, to: context)
        addWalk(along: Array(aroundPark.prefix(40)), dogs: [bello], startedAt: .now - day / 3, to: context)
        addWalk(along: Array(aroundStation.prefix(30)), dogs: [rex], startedAt: .now - 400 * day, to: context)
        rex.retire(on: .now - 300 * day, reason: "Old age")
        if let huettikon = try? MapPackages.bundled.shape(of: huettikon) {
            addWalk(along: nearestFirst(huettikon.segments), dogs: [bello], startedAt: .now - 2 * day, to: context)
        }

        context.insert(PinnedArea(area: dietikon))
        context.insert(PinnedArea(area: schlieren))
        context.insert(PinnedArea(area: huettikon))
        try? context.save()
    }

    private static func segments(
        of shape: AreaShape, near center: CLLocationCoordinate2D, withinMetres radius: Double
    ) -> [Segment] {
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return shape.segments.filter { segment in
            guard let first = segment.coordinates.first else { return false }
            return CLLocation(latitude: first.latitude, longitude: first.longitude)
                .distance(from: centerLocation) <= radius
        }
    }

    /// The segments in an order that goes each time to the segment whose
    /// start is nearest to the end of the one before, so that a walk along
    /// them makes few long jumps.
    private static func nearestFirst(_ segments: [Segment]) -> [Segment] {
        var left = segments
        var ordered: [Segment] = []
        var end = left.first?.coordinates.first
        while let from = end, !left.isEmpty {
            let index = left.indices.min { a, b in
                squaredDistance(from, left[a].coordinates.first) < squaredDistance(from, left[b].coordinates.first)
            }!
            let next = left.remove(at: index)
            ordered.append(next)
            end = next.coordinates.last
        }
        return ordered
    }

    private static func squaredDistance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D?) -> Double {
        guard let b else { return .infinity }
        return pow(a.latitude - b.latitude, 2) + pow((a.longitude - b.longitude) * 0.68, 2)
    }

    /// A walk along the segments one after the other, with a point every 5 m
    /// at walking speed.
    private static func addWalk(along segments: [Segment], dogs: [Dog], startedAt: Date, to context: ModelContext) {
        let speed = 1.4
        var time = startedAt
        var points: [TrackPoint] = []
        var previous: CLLocation?
        for coordinate in segments.flatMap(\.coordinates) {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let previous {
                let distance = location.distance(from: previous)
                let steps = max(Int((distance / 5).rounded(.up)), 1)
                for step in 1...steps {
                    let share = Double(step) / Double(steps)
                    time += distance / Double(steps) / speed
                    points.append(TrackPoint(
                        latitude: previous.coordinate.latitude + (coordinate.latitude - previous.coordinate.latitude) * share,
                        longitude: previous.coordinate.longitude + (coordinate.longitude - previous.coordinate.longitude) * share,
                        timestamp: time, horizontalAccuracy: 5))
                }
            } else {
                points.append(TrackPoint(
                    latitude: coordinate.latitude, longitude: coordinate.longitude, timestamp: time, horizontalAccuracy: 5))
            }
            previous = location
        }
        let walk = Walk(startedAt: startedAt, dogs: dogs)
        walk.store(Track(points: points))
        walk.endedAt = time
        context.insert(walk)
    }
}
#endif
