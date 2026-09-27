//
//  AreaScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// The completion of one area for one dog, the number of collected segments,
/// the date if the dog has completed the area, and a map of the area's
/// segments. It needs a navigation stack around it.
struct AreaScreen: View {
    let page: CollectionBook.Page
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
        }
        .navigationTitle(page.area.name)
        .navigationSubtitle("Canton \(page.area.canton)")
    }
}

extension Completion {
    /// The completion as a percentage. It rounds down, so that an area shows
    /// 100% only when it is completed.
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
            dogName: "Bello")
    }
}
