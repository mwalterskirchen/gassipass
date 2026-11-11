//
//  MapScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import GassiPassCore
import SwiftData
import SwiftUI

/// Shows the segments of the bundled map packages on the swisstopo base map.
/// Without a track, each segment shows as collected or not collected for the
/// chosen dog of the app, a collected segment paler as its mark fades, and a
/// tap on a segment opens the screen of its area. With the track of a walk,
/// the screen shows the track and the segments that the walk collected.
///
/// Around the home base, which the ring card opens, the map frames the
/// current ring of the dog as a circle, and shows its nearest new segments
/// in a stronger style.
///
/// With a street, which a weekly goal opens, the map frames the street and
/// shows its segments that the dog has not collected in the stronger style.
struct MapScreen: View {
    var track: Track?
    /// With a track, the feature IDs of the segments that the walk collected.
    var collectedOnWalk: Set<Int> = []
    /// Whether the map shows the current ring around the home base.
    var showsHomeBase = false
    /// The street that the map frames and shows in a stronger style.
    var street: Street.ID?

    @Environment(Collections.self) private var collections
    @Environment(DogChoice.self) private var dogChoice
    @Query(Dog.all()) private var dogs: [Dog]
    /// Whether the map packages open, or nil until they are tried.
    @State private var openResult: Result<Void, any Error>?
    @State private var selectedArea: Area?
    /// The segments of the street, or nil until they are read.
    @State private var streetSegments: [Segment]?

    var body: some View {
        // The status sorts the segments around the home base, so it is read once.
        let ringStatus = ringStatus
        Group {
            switch openResult {
            case .success:
                SegmentMapView(
                    track: track?.filteredPoints.map(\.coordinate) ?? [],
                    markedFeatures: showsCollection
                        ? collections.markedFeatures(of: shownDog?.id)
                        : MarkedFeatures(collected: collectedOnWalk),
                    highlightedFeatures: Set(
                        (streetSegments ?? []).map(\.fid) + (ringStatus?.nearestNewSegments.map(\.fid) ?? [])),
                    ring: ringStatus?.ring,
                    framedCoordinates: (streetSegments ?? []).flatMap(\.coordinates),
                    framesRing: showsHomeBase, centre: homeBaseCentre,
                    onSelectArea: showsCollection ? { selectedArea = collections.areas[$0] } : nil)
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        if showsCollection && !dogs.isEmpty {
                            legend
                        }
                    }
                    .mapAttribution()
                    .sheet(item: $selectedArea) { area in
                        NavigationStack {
                            AreaScreen(area: area, dog: shownDog, collections: collections)
                        }
                        .presentationDetents([.medium, .large])
                    }
            case .failure(let error):
                ContentUnavailableView(
                    "The map package cannot open", systemImage: "map",
                    description: Text(String(describing: error)))
            case nil:
                ProgressView()
            }
        }
        .task {
            // The task runs each time the tab appears, but the packages are checked only once.
            guard openResult == nil else { return }
            do {
                try await MapPackages.bundled.check()
                // The map frames the street when it appears, so it waits
                // for the segments.
                if let street {
                    streetSegments = await Self.segments(of: street)
                }
                openResult = .success(())
            } catch {
                openResult = .failure(error)
            }
        }
    }

    /// The segments of the street, read off the main thread. A street that
    /// the map packages no longer hold has none, and the map then starts
    /// like the map tab.
    @concurrent nonisolated private static func segments(of street: Street.ID) async -> [Segment] {
        (try? MapPackages.bundled.segments(of: street)) ?? []
    }

    private var showsCollection: Bool {
        track == nil
    }

    private var shownDog: Dog? {
        dogChoice.shownDog(in: dogs)
    }

    /// The current ring of the shown dog, on the map around the home base.
    private var ringStatus: RingStatus? {
        guard showsHomeBase, let dog = shownDog else { return nil }
        return collections.ringStatus(of: dog.id)
    }

    /// The home base, on the map around the home base.
    private var homeBaseCentre: CLLocationCoordinate2D? {
        showsHomeBase ? collections.homeBase?.coordinate : nil
    }

    /// The dog picker, when there is more than one dog, and the legend of the
    /// segments.
    private var legend: some View {
        HStack(spacing: 12) {
            if dogs.count > 1 {
                DogPicker(dogs: dogs)
            }
            Label("Collected", systemImage: "circle.fill")
                .labelStyle(MapLegendLabelStyle(isCollected: true))
            Label("Not collected", systemImage: "circle.fill")
                .labelStyle(MapLegendLabelStyle(isCollected: false))
        }
        .font(.footnote)
        // The menu of the picker has its own padding.
        .padding(.leading, dogs.count > 1 ? 4 : 14)
        .padding(.trailing, 14)
        .padding(.vertical, 2)
        .glassEffect(in: .capsule)
        .padding(.top, 8)
    }
}

#Preview {
    MapScreen()
        .environment(Collections.preview())
        .environment(DogChoice())
        .modelContainer(.preview)
}
