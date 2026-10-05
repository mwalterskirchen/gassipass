//
//  AreaScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// The completion of one area for one dog, the number of collected segments,
/// a map of the area's segments with a stamp if the dog has completed the
/// area, and its streets with their completion or a date stamp. The user
/// can sort the streets, and pin and unpin the area here. It needs a
/// navigation stack around it.
struct AreaScreen: View {
    let page: CollectionBook.Page
    let streets: [CollectionBook.StreetEntry]
    /// The name of the dog, or nil if there is no dog yet.
    let dogName: String?
    @Environment(\.modelContext) private var modelContext
    @Query private var pins: [PinnedArea]
    @AppStorage(OrderMenu.key) private var order: CollectionBook.Order = OrderMenu.defaultOrder

    var body: some View {
        List {
            Section {
                hero
                    .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
            }
            if !streets.isEmpty {
                Section {
                    ForEach(CollectionBook.sorted(streets, by: order)) { entry in
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
            if !streets.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    OrderMenu()
                }
            }
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
                .overlay(alignment: .bottomTrailing) {
                    if let completedAt = page.completedAt {
                        // Beside the completion, and on a disc in the colour
                        // of the card, so that the lines of the map do not
                        // cross the ink.
                        Stamp(
                            area: page.area.id, name: page.area.name, dogNames: dogName.map { [$0] } ?? [],
                            date: completedAt, size: 124)
                            .padding(6)
                            .background(Color(.secondarySystemGroupedBackground), in: .circle)
                            .offset(x: 4, y: 76)
                    }
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(page.completion.formattedShare)
                    .monospacedDigit()
                    .bigFiguresFont(size: 56)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                CompletionBar(share: page.completion.share)
                    .padding(.bottom, 4)
                Text(summary)
                    .font(.subheadline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.secondary)
            }
            .animatesChange(of: page.completion)
            .accessibilityElement(children: .combine)
        }
    }

    private var summary: LocalizedStringResource {
        let collected = page.completion.collectedSegmentCount.formatted()
        let total = page.completion.segmentCount.formatted()
        guard let dogName else { return "\(collected) of \(total) segments collected" }
        return "\(dogName) has collected \(collected) of \(total) segments."
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
            Text(entry.street.name)
            Spacer()
            if let completedAt = entry.completedAt {
                DateStamp(date: completedAt)
            } else {
                Text(entry.completion.formattedShare)
                    .font(.figures(.body))
                    .monospacedDigit()
                    .foregroundStyle(entry.completion.collectedSegmentCount == 0 ? .tertiary : .primary)
            }
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
    .modelContext(.preview())
}
