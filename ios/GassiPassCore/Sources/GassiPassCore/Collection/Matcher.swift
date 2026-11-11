//
//  Matcher.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation

/// The part of an update that runs off the main actor: it reads the map
/// packages and the stored matches, and matches the walks.
nonisolated struct Matcher: Sendable {
    /// The history to add to, and the dogs that each walk adds to it.
    struct Plan: Sendable {
        let history: CollectionHistory
        /// The walks to add and their dogs, in the order of time, so that
        /// most walks follow the intervals that the history keeps.
        let additions: [(key: WalkMatchCache.Key, dogs: Set<UUID>)]
        /// All ended walks, whose stored matches stay.
        let walks: Set<WalkMatchCache.Key>
    }

    /// What the first step reads.
    struct Stored: Sendable {
        let cache: WalkMatchCache?
        let matches: [WalkMatchCache.Key: WalkMatch]
        /// The areas, the streets and the cantons, if the step loaded them.
        let loadedAreas: LoadedAreas?
    }

    /// The history after a rebuild, and whether every walk has a match. A
    /// walk whose track cannot be read has none.
    struct Rebuilt: Sendable {
        let history: CollectionHistory
        let matchedEveryWalk: Bool
        /// The marks of each added walk that started at the date of the
        /// rebuild or later.
        let marks: [WalkMatchCache.Key: [Segment.ID: Date]]
    }

    struct LoadedAreas: Sendable {
        let areas: [Int: Area]
        let streets: [Int: [Street]]
        let cantons: [String]
    }

    let packages: MapPackages
    let cacheRoot: URL?

    /// The identity of the map packages, of which the version of the
    /// collections follows (`CacheFolder.version(packages:)`).
    @concurrent func identity() async throws -> String {
        try packages.identity()
    }

    /// The walks that the history does not hold yet, and the history to add
    /// them to (`CollectionHistory.prepared(for:dogs:)`). Without a history
    /// of this version, the plan adds all walks to an empty one.
    @concurrent func plan(for input: CollectionInput, history: CollectionHistory?) async throws -> Plan {
        var current: [WalkMatchCache.Key: Set<UUID>] = [:]
        for walk in input.walks {
            if let key = walk.key {
                current[key, default: []].formUnion(walk.dogs.intersection(input.dogs))
            }
        }
        let prepared = (history ?? CollectionHistory()).prepared(for: current, dogs: input.dogs)
        return Plan(
            history: prepared.history,
            additions: prepared.additions.map { (key: $0.key, dogs: $0.value) }.sorted { $0.key.startedAt < $1.key.startedAt },
            walks: Set(current.keys))
    }

    /// The stored match of each walk that has one, and the areas and the
    /// streets if they are needed.
    @concurrent func stored(for keys: [WalkMatchCache.Key], loadsAreas: Bool, identity: String) async throws -> Stored {
        let cache = cacheRoot.flatMap { WalkMatchCache.forPackages(identity, in: $0) }
        var matches: [WalkMatchCache.Key: WalkMatch] = [:]
        for key in keys {
            matches[key] = cache?.match(for: key)
        }
        return Stored(cache: cache, matches: matches, loadedAreas: loadsAreas ? try loadAreas() : nil)
    }

    /// The marks of the walks whose matches are stored. A walk without a
    /// stored match has none.
    @concurrent func marks(for keys: [WalkMatchCache.Key]) async throws -> [WalkMatchCache.Key: [Segment.ID: Date]] {
        let identity = try packages.identity()
        let cache = cacheRoot.flatMap { WalkMatchCache.forPackages(identity, in: $0) }
        var marks: [WalkMatchCache.Key: [Segment.ID: Date]] = [:]
        for key in keys {
            try Task.checkCancellation()
            marks[key] = cache?.match(for: key)?.marks
        }
        return marks
    }

    /// The segments whose midpoints lie within the radius of the home base.
    @concurrent func ringSegments(around centre: HomeBase, withinMetres radius: Double) async throws -> RingSegments {
        let segments = try packages.segments(in: [RingSegments.box(around: centre, withinMetres: radius)])
        return RingSegments(centre: centre, segments: segments, radiusMetres: radius)
    }

    private func loadAreas() throws -> LoadedAreas {
        let areas = try packages.areas()
        let streets = try packages.streets()
        return LoadedAreas(
            areas: Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            streets: Dictionary(grouping: streets, by: \.id.area),
            cantons: Set(areas.map(\.canton)).sorted())
    }

    /// Adds the walks of the plan to its history. It matches the walks that
    /// have no stored match, and stores their matches.
    ///
    /// A track that cannot be read collects nothing, as it shows as empty.
    /// Neither its match nor the walk in the history is stored, so that the
    /// next update tries it again.
    ///
    /// - Parameter marksSince: The rebuild gives the marks of the added walks
    ///   that started at this date or later.
    @concurrent func collections(
        adding plan: Plan, stored: Stored, trackData: [WalkMatchCache.Key: Data?], marksSince: Date
    ) async throws -> Rebuilt {
        var matches = stored.matches
        var matchedEveryWalk = true
        if !trackData.isEmpty {
            let tracks = trackData.mapValues { data in data.flatMap { try? Track(data: $0) } }
            matchedEveryWalk = !tracks.values.contains(nil)
            let engine = try packages.engine(covering: tracks.values.compactMap { $0 })
            for (key, track) in tracks {
                try Task.checkCancellation()
                guard let track else { continue }
                let match = engine.match(track)
                matches[key] = match
                stored.cache?.store(match, for: key)
            }
        }
        var history = plan.history
        var marks: [WalkMatchCache.Key: [Segment.ID: Date]] = [:]
        for (key, dogs) in plan.additions {
            try Task.checkCancellation()
            guard let match = matches[key] else { continue }
            history.add(match, of: key, for: dogs)
            if key.startedAt >= marksSince {
                marks[key] = match.marks
            }
        }
        try Task.checkCancellation()
        stored.cache?.removeAll(except: plan.walks)
        return Rebuilt(history: history, matchedEveryWalk: matchedEveryWalk, marks: marks)
    }
}
