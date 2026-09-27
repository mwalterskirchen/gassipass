//
//  AreaScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// The completion of one area for one dog, the number of collected segments,
/// the date if the dog has completed the area, a map of the area's segments,
/// and its streets with their completion. It needs a navigation stack
/// around it.
struct AreaScreen: View {
    let page: CollectionBook.Page
    let streets: [CollectionBook.StreetEntry]
    /// The name of the dog, or nil if there is no dog yet.
    let dogName: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Completion", value: page.completion.formattedShare)
                LabeledContent("Collected segments",
                               value: "\(page.completion.collectedSegmentCount) of \(page.completion.segmentCount)")
                if let completedAt = page.completedAt {
                    LabeledContent("Completed", value: completedAt.formatted(date: .long, time: .omitted))
                }
            } header: {
                if let dogName {
                    Text(dogName)
                }
            }
            Section {
                AreaMap(area: page.area.id, collectedSegments: page.collectedSegments)
                    .frame(height: 280)
            }
            if !streets.isEmpty {
                Section {
                    ForEach(streets) { entry in
                        StreetRow(entry: entry)
                    }
                } header: {
                    Text("Streets: \(streets.count { $0.completedAt != nil }) of \(streets.count) completed")
                }
            }
        }
        .navigationTitle(page.area.name)
        .navigationSubtitle("Canton \(page.area.canton)")
    }
}

private struct StreetRow: View {
    let entry: CollectionBook.StreetEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.street.name)
                if let completedAt = entry.completedAt {
                    Label(completedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color(SegmentMapView.collectedColor))
                        .font(.subheadline)
                }
            }
            Spacer()
            Text(entry.completion.formattedShare)
                .monospacedDigit()
                .foregroundStyle(entry.completion.collectedSegmentCount == 0 ? .secondary : .primary)
        }
    }
}

extension Completion {
    /// The completion as a percentage. It rounds down, so that an area or a
    /// street shows 100% only when it is completed.
    var formattedShare: String {
        share.formatted(.percent.precision(.fractionLength(0...1)).rounded(rule: .down))
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
                collectedSegments: []),
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
}
