//
//  MapScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// Shows the segments of the bundled map packages on the swisstopo base map.
/// Without a track, each segment shows as collected or not collected for the
/// chosen dog of the app, and a tap on a segment opens the screen of
/// its area. With the track of a walk, the screen shows only the track.
struct MapScreen: View {
    var track: Track?

    @Environment(Collections.self) private var collections
    @Environment(DogChoice.self) private var dogChoice
    @Query(sort: \Dog.name) private var dogs: [Dog]
    @State private var loadResult: Result<[MapPackage], any Error>?
    @State private var selectedArea: Area?

    var body: some View {
        Group {
            switch loadResult {
            case .success(let packages):
                SegmentMapView(
                    packages: packages, track: track?.coordinates ?? [],
                    collectedSegmentIDs: showsCollection
                        ? collections.collection(of: shownDog?.persistentModelID).collectedSegments : [],
                    onSelectArea: showsCollection ? { selectedArea = collections.areas[$0] } : nil)
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        if showsCollection && !dogs.isEmpty {
                            dogPicker
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
            loadResult = Result { try MapPackage.bundled() }
        }
    }

    private var showsCollection: Bool {
        track == nil
    }

    private var shownDog: Dog? {
        dogChoice.shownDog(in: dogs)
    }

    private var dogPicker: some View {
        HStack(spacing: 12) {
            DogPicker(dogs: dogs)
            Label("Collected", systemImage: "circle.fill")
                .foregroundStyle(Color(SegmentMapView.collectedColor))
            Label("Not collected", systemImage: "circle.fill")
                .foregroundStyle(Color(SegmentMapView.notCollectedColor))
        }
        .font(.footnote)
        .labelStyle(LegendLabelStyle())
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 8)
    }
}

/// A small coloured dot before the title.
private struct LegendLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .imageScale(.small)
            configuration.title
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    MapScreen()
        .environment(Collections())
        .environment(DogChoice())
}
