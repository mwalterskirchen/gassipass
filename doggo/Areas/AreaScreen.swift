//
//  AreaScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// The completion of one area for one dog, the number of collected segments,
/// the date if the dog has completed the area, a map of the area's segments,
/// and its streets with their completion. The user can pin and unpin the
/// area here. It needs a navigation stack around it.
struct AreaScreen: View {
    let page: CollectionBook.Page
    let streets: [CollectionBook.StreetEntry]
    /// The name of the dog, or nil if there is no dog yet.
    let dogName: String?
    @Environment(\.modelContext) private var modelContext
    @Query private var pins: [PinnedArea]

    var body: some View {
        List {
            Section {
                hero
                    .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
            }
            if !streets.isEmpty {
                Section {
                    ForEach(streets) { entry in
                        StreetRow(entry: entry)
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Streets")
                        Spacer()
                        Text("\(streets.count { $0.completedAt != nil }) of \(streets.count) completed")
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle(page.area.name)
        .navigationSubtitle("Canton \(page.area.canton)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if pinsOfArea.isEmpty {
                    Button("Pin", systemImage: "pin") {
                        modelContext.insert(PinnedArea(area: page.area.id))
                    }
                } else {
                    Button("Unpin", systemImage: "pin.slash") {
                        pinsOfArea.forEach(modelContext.delete)
                    }
                }
            }
        }
    }

    /// The map of the area and its completion for the dog.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            AreaMap(area: page.area.id, collectedFeatures: page.collectedFeatures)
                .frame(height: 260)
            VStack(alignment: .leading, spacing: 8) {
                Text(page.completion.formattedShare)
                    .font(.bigFigures(size: 56))
                    .monospacedDigit()
                CompletionBar(share: page.completion.share)
                    .padding(.bottom, 4)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let completedAt = page.completedAt {
                    Label {
                        Text("Completed on \(completedAt.formatted(date: .long, time: .omitted))")
                    } icon: {
                        CompletedSeal()
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var summary: String {
        let segments = "\(page.completion.collectedSegmentCount.formatted()) of \(page.completion.segmentCount.formatted()) segments"
        guard let dogName else { return "\(segments) collected" }
        return "\(dogName) has collected \(segments)."
    }

    /// The pins of the area. With two devices there can be more than one.
    private var pinsOfArea: [PinnedArea] {
        pins.filter { $0.area == page.area.id }
    }
}

extension AreaScreen {
    /// The screen of the area for the dog. Without a dog, the area shows
    /// with nothing collected.
    init(area: Area, dog: Dog?, collections: Collections) {
        let streets = collections.streets[area.id] ?? []
        guard let dog else {
            self.init(
                page: CollectionBook.page(of: area, collection: DogCollection(), dog: 0, records: []),
                streets: CollectionBook.streets(
                    of: area.id, streets: streets, collection: DogCollection(), dog: 0, records: []),
                dogName: nil)
            return
        }
        let collection = collections.collection(of: dog.persistentModelID)
        self.init(
            page: CollectionBook.page(
                of: area, collection: collection, dog: dog.persistentModelID, records: dog.completedAreaRecords),
            streets: CollectionBook.streets(
                of: area.id, streets: streets, collection: collection, dog: dog.persistentModelID,
                records: dog.completedStreetRecords),
            dogName: dog.name)
    }
}

private struct StreetRow: View {
    let entry: CollectionBook.StreetEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.street.name)
                if let completedAt = entry.completedAt {
                    Label {
                        Text(completedAt.formatted(date: .abbreviated, time: .omitted))
                    } icon: {
                        CompletedSeal()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.completion.formattedShare)
                .font(.figures(.body))
                .monospacedDigit()
                .foregroundStyle(entry.completion.collectedSegmentCount == 0 ? .tertiary : .primary)
        }
        .accessibilityElement(children: .combine)
    }
}

extension Completion {
    /// The completion as a percentage. It rounds down, so that an area or a
    /// street shows 100% only when it is completed.
    var formattedShare: String {
        share.formatted(.completionShare)
    }
}

#Preview {
    NavigationStack {
        AreaScreen(
            page: CollectionBook.Page(
                area: Area(id: 243, name: "Dietikon", canton: "ZH", segmentCount: 2232, lengthMetres: 173_470),
                completion: Completion(collectedLengthMetres: 12_300, lengthMetres: 173_470,
                                       collectedSegmentCount: 148, segmentCount: 2232),
                completedAt: nil,
                collectedFeatures: []),
            streets: [
                CollectionBook.StreetEntry(
                    street: Street(id: Street.ID(area: 243, name: "Bahnhofstrasse"), segmentCount: 12, lengthMetres: 640),
                    completion: Completion(collectedLengthMetres: 640, lengthMetres: 640,
                                           collectedSegmentCount: 12, segmentCount: 12),
                    completedAt: .now),
                CollectionBook.StreetEntry(
                    street: Street(id: Street.ID(area: 243, name: "Zürcherstrasse"), segmentCount: 20, lengthMetres: 1800),
                    completion: Completion(collectedLengthMetres: 450, lengthMetres: 1800,
                                           collectedSegmentCount: 5, segmentCount: 20),
                    completedAt: nil),
            ],
            dogName: "Bello")
    }
    .modelContainer(for: PinnedArea.self, inMemory: true)
}
