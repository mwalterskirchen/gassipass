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
/// dog that the walker chooses, and a tap on a segment opens the screen of
/// its area. With the track of a walk, the screen shows only the track.
struct MapScreen: View {
    var track: Track?

    @Environment(Collections.self) private var collections
    @Query(sort: \Dog.name) private var dogs: [Dog]
    @State private var loadResult: Result<[MapPackage], any Error>?
    @State private var chosenDogID: PersistentIdentifier?
    @State private var selectedArea: Area?

    var body: some View {
        Group {
            switch loadResult {
            case .success(let packages):
                SegmentMapView(
                    packages: packages, track: track?.coordinates ?? [],
                    collectedSegmentIDs: showsCollection ? collections.collection(of: shownDogID).collectedSegments : [],
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
                            areaScreen(area)
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

    /// The dog whose collection the map shows: the chosen dog, else the first.
    private var shownDogID: PersistentIdentifier? {
        chosenDogID ?? dogs.first?.persistentModelID
    }

    private var dogPicker: some View {
        HStack(spacing: 12) {
            Picker("Dog", selection: Binding(get: { shownDogID }, set: { chosenDogID = $0 })) {
                ForEach(dogs) { dog in
                    Text(dog.name).tag(Optional(dog.persistentModelID))
                }
            }
            .pickerStyle(.menu)
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

    private func areaScreen(_ area: Area) -> AreaScreen {
        let dog = dogs.first { $0.persistentModelID == shownDogID }
        // Without a dog, the area shows with nothing collected.
        let page = dog.map {
            CollectionBook.page(
                of: area, collection: collections.collection(of: $0.persistentModelID),
                dog: $0.persistentModelID, records: $0.completedRecords)
        } ?? CollectionBook.page(of: area, collection: DogCollection(), dog: 0, records: [])
        return AreaScreen(page: page, dogName: dog?.name)
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
}
