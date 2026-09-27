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
/// dog that the walker chooses. With the track of a walk, the screen shows
/// only the track.
struct MapScreen: View {
    var track: Track?

    @Query(sort: \Dog.name) private var dogs: [Dog]
    /// A walk counts when it has ended. Live matching during a walk comes later.
    @Query(filter: #Predicate<Walk> { $0.endedAt != nil }) private var walks: [Walk]
    @State private var loadResult: Result<[MapPackage], any Error>?
    @State private var chosenDogID: PersistentIdentifier?
    @State private var collections: [PersistentIdentifier: DogCollection] = [:]

    var body: some View {
        Group {
            switch loadResult {
            case .success(let packages):
                SegmentMapView(
                    packages: packages, track: track?.coordinates ?? [],
                    collectedSegmentIDs: shownDogID.flatMap { collections[$0]?.collectedSegments } ?? [])
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
                    .task(id: collectionInput) {
                        guard showsCollection else { return }
                        await rebuildCollections()
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

    /// What the collections depend on. A change starts a new rebuild.
    private var collectionInput: [WalkInput] {
        walks.map { WalkInput(walk: $0.persistentModelID, dogs: Self.dogIDs(of: $0)) }
    }

    /// Rebuilds the collections of all dogs from all walks, off the main
    /// thread. The rebuild opens its own packages, because the map view reads
    /// the others on the main thread at the same time.
    private func rebuildCollections() async {
        let dogIDs = Set(dogs.map(\.persistentModelID))
        let walkData = walks.map { (dogs: Self.dogIDs(of: $0), trackData: $0.trackData) }
        let result = await Task.detached(priority: .userInitiated) { () -> [PersistentIdentifier: DogCollection]? in
            // A track that cannot be read collects nothing, as it shows as empty.
            let engineWalks = walkData.map { walk in
                CollectionEngine.Walk(
                    dogs: walk.dogs, track: (try? walk.trackData.map(Track.init(data:))) ?? Track())
            }
            guard let packages = try? MapPackage.bundled() else { return nil }
            // The packages are too big to load at once, so the engine gets
            // only the segments that the walks can cover.
            var segments: [Segment.ID: Segment] = [:]
            for box in engineWalks.flatMap({ CollectionEngine.coverableBoxes(of: $0.track) }) {
                for package in packages {
                    for segment in (try? package.segments(in: box)) ?? [] {
                        segments[segment.id] = segment
                    }
                }
            }
            return CollectionEngine(segments: Array(segments.values)).rebuild(dogs: dogIDs, walks: engineWalks)
        }.value
        guard !Task.isCancelled, let result else { return }
        collections = result
    }

    private static func dogIDs(of walk: Walk) -> Set<PersistentIdentifier> {
        Set((walk.dogs ?? []).map(\.persistentModelID))
    }
}

private struct WalkInput: Equatable {
    let walk: PersistentIdentifier
    let dogs: Set<PersistentIdentifier>
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
}
