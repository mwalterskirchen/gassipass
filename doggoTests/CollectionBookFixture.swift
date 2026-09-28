//
//  CollectionBookFixture.swift
//  doggoTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import Testing
@testable import doggo

/// Two invented areas in canton Zürich and one in canton Aargau, with
/// segments far enough apart that a walk along one does not touch another.
protocol CollectionBookFixture {}

extension CollectionBookFixture {
    var long: Segment {
        straightSegment(id: "long", fid: 1, area: 9001, startLatitude: 47.400, startLongitude: 8.400, eastMetres: 1000)
    }
    var short: Segment {
        straightSegment(id: "short", fid: 2, area: 9001, startLatitude: 47.402, startLongitude: 8.400, eastMetres: 100)
    }
    var other: Segment {
        straightSegment(id: "other", fid: 3, area: 9002, startLatitude: 47.404, startLongitude: 8.400, eastMetres: 300)
    }
    var aargau: Segment {
        straightSegment(id: "aargau", fid: 4, area: 9101, startLatitude: 47.406, startLongitude: 8.400, eastMetres: 400)
    }
    var areas: [Area] {
        [
            Area(id: 9002, name: "Zelgli", canton: "ZH", segmentCount: 1, lengthMetres: 300),
            Area(id: 9101, name: "Aarau Test", canton: "AG", segmentCount: 1, lengthMetres: 400),
            Area(id: 9001, name: "Äsch", canton: "ZH", segmentCount: 2, lengthMetres: 1100),
        ]
    }
    var start: Date { Date(timeIntervalSinceReferenceDate: 812_000_000) }

    /// The collection of Bello after one walk along each segment, one day apart.
    func collection(walking segments: [Segment]) throws -> DogCollection {
        let engine = CollectionEngine(segments: [long, short, other, aargau])
        let walks = segments.enumerated().map { index, segment in
            CollectionEngine.Walk(
                dogs: ["Bello"], track: syntheticTrack(along: segment, startingAt: start + Double(index) * 86_400))
        }
        return try #require(engine.rebuild(dogs: ["Bello"], walks: walks)["Bello"])
    }
}
