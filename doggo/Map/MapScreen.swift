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
///
/// After each rebuild of the collections, the screen stores the new
/// completed records.
struct MapScreen: View {
    var track: Track?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dog.name) private var dogs: [Dog]
    /// A walk counts when it has ended. Live matching during a walk comes later.
    @Query(filter: #Predicate<Walk> { $0.endedAt != nil }) private var walks: [Walk]
    @State private var loadResult: Result<[MapPackage], any Error>?
    @State private var chosenDogID: PersistentIdentifier?
    @State private var collections: [PersistentIdentifier: DogCollection] = [:]
    /// The areas of all packages by BFS number, empty until they are loaded.
    @State private var areas: [Int: Area] = [:]
    @State private var selectedArea: Area?

    var body: some View {
        Group {
            switch loadResult {
            case .success(let packages):
                SegmentMapView(
                    packages: packages, track: track?.coordinates ?? [],
                    collectedSegmentIDs: shownDogID.flatMap { collections[$0]?.collectedSegments } ?? [],
                    onSelectArea: showsCollection ? { selectedArea = areas[$0] } : nil)
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
                    .task {
                        guard showsCollection else { return }
                        await loadAreas()
                    }
                    .sheet(item: $selectedArea) { area in
                        areaScreen(area)
                            .presentationDetents([.medium])
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
        let completion = (shownDogID.flatMap { collections[$0] } ?? DogCollection()).completion(of: area)
        let completedAt = shownDogID.flatMap {
            CollectionEngine.completedDate(of: area.id, for: $0, in: storedRecords)
        }
        return AreaScreen(area: area, dogName: dog?.name, completion: completion, completedAt: completedAt)
    }

    /// Loads the areas off the main thread, from packages of its own, like
    /// the rebuild.
    private func loadAreas() async {
        let loaded = await Task.detached(priority: .userInitiated) { () -> [Int: Area] in
            let packages = (try? MapPackage.bundled()) ?? []
            let areas = packages.flatMap { (try? $0.areas()) ?? [] }
            return Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }.value
        guard !Task.isCancelled else { return }
        areas = loaded
        recordCompletedAreas()
    }

    /// The stored completed records of all dogs. They come from the dogs'
    /// relationships, which change at once when a record is inserted.
    private var storedRecords: [CompletedRecord<PersistentIdentifier>] {
        dogs.flatMap { dog in
            (dog.completedAreas ?? []).map {
                CompletedRecord(dog: dog.persistentModelID, area: $0.area, date: $0.completedAt)
            }
        }
    }

    /// Stores each record that the engine reports for a dog and area that
    /// has no stored record yet.
    private func recordCompletedAreas() {
        guard !areas.isEmpty, !collections.isEmpty else { return }
        let existing = storedRecords
        let records = CollectionEngine.completedRecords(
            collections: collections, areas: Array(areas.values), existing: existing)
        for record in records
        where CollectionEngine.completedDate(of: record.area, for: record.dog, in: existing) == nil {
            guard let dog = dogs.first(where: { $0.persistentModelID == record.dog }) else { continue }
            modelContext.insert(CompletedArea(dog: dog, area: record.area, completedAt: record.date))
        }
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
        recordCompletedAreas()
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
