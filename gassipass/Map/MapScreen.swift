//
//  MapScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// Shows the segments of the bundled map packages on the swisstopo base map.
/// Without a track, each segment shows as collected or not collected for the
/// chosen dog of the app, and a tap on a segment opens the screen of
/// its area. With the track of a walk, the screen shows the track and the
/// segments that the walk collected.
struct MapScreen: View {
    var track: Track?
    /// With a track, the feature IDs of the segments that the walk collected.
    var collectedOnWalk: Set<Int> = []

    @Environment(Collections.self) private var collections
    @Environment(DogChoice.self) private var dogChoice
    @Query(sort: \Dog.name) private var dogs: [Dog]
    /// Whether the map packages open, or nil until they are tried.
    @State private var openResult: Result<Void, any Error>?
    @State private var selectedArea: Area?

    var body: some View {
        Group {
            switch openResult {
            case .success:
                SegmentMapView(
                    track: track?.filteredPoints.map(\.coordinate) ?? [],
                    collectedFeatures: showsCollection
                        ? collections.collection(of: shownDog?.persistentModelID).collectedFeatures : collectedOnWalk,
                    onSelectArea: showsCollection ? { selectedArea = collections.areas[$0] } : nil)
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        if showsCollection && !dogs.isEmpty {
                            legend
                        }
                    }
                    .overlay(alignment: .bottom) {
                        MapAttribution()
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                    }
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
                openResult = .success(())
            } catch {
                openResult = .failure(error)
            }
        }
    }

    private var showsCollection: Bool {
        track == nil
    }

    private var shownDog: Dog? {
        dogChoice.shownDog(in: dogs)
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

/// A short line in the style of the map before the title: solid apricot for
/// collected segments, dashed green for segments that are not collected.
struct MapLegendLabelStyle: LabelStyle {
    let isCollected: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Canvas { context, size in
                var line = Path()
                line.move(to: CGPoint(x: 2, y: size.height / 2))
                line.addLine(to: CGPoint(x: size.width - 2, y: size.height / 2))
                if isCollected {
                    context.stroke(line, with: .color(.collectedEdge),
                                   style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    context.stroke(line, with: .color(.collected),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round))
                } else {
                    context.stroke(line, with: .color(.notCollected),
                                   style: StrokeStyle(lineWidth: 2.5, dash: [5, 3.5]))
                }
            }
            .frame(width: 20, height: 8)
            configuration.title
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    MapScreen()
        .environment(Collections.preview())
        .environment(DogChoice())
}
