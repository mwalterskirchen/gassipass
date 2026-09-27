//
//  AreaScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// The completion of one area for one dog, the number of collected segments
/// and, if the dog has completed the area, the date.
struct AreaScreen: View {
    let area: Area
    /// The name of the dog, or nil if there is no dog yet.
    let dogName: String?
    let completion: Completion
    let completedAt: Date?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Completion", value: completion.share.formatted(
                        .percent.precision(.fractionLength(0...1)).rounded(rule: .down)))
                    LabeledContent("Collected segments",
                                   value: "\(completion.collectedSegmentCount) of \(completion.segmentCount)")
                    if let completedAt {
                        LabeledContent("Completed", value: completedAt.formatted(date: .long, time: .omitted))
                    }
                } header: {
                    if let dogName {
                        Text(dogName)
                    }
                }
            }
            .navigationTitle(area.name)
            .navigationSubtitle("Canton \(area.canton)")
        }
    }
}

#Preview {
    AreaScreen(
        area: Area(id: 243, name: "Dietikon", canton: "ZH", segmentCount: 2232, lengthMetres: 173_470),
        dogName: "Bello",
        completion: Completion(collectedLengthMetres: 12_300, lengthMetres: 173_470,
                               collectedSegmentCount: 148, segmentCount: 2232),
        completedAt: nil)
}
