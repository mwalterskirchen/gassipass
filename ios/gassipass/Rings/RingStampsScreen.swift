//
//  RingStampsScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import SwiftUI

/// The page of the collection book with the ring stamps of one dog, by the
/// number of the ring, also the stamps of an old home base.
struct RingStampsScreen: View {
    let dog: Dog

    @Environment(Collections.self) private var collections

    var body: some View {
        let stamps = collections.ringRecords(of: dog.id).sorted { ($0.goal.number, $0.date) < ($1.goal.number, $1.date) }
        Group {
            if stamps.isEmpty {
                ContentUnavailableView(
                    "No Ring Stamps", systemImage: "circle.dashed",
                    description: Text("A dog gets a ring stamp when it completes a ring around the home base."))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 24) {
                        ForEach(stamps, id: \.self) { stamp in
                            Stamp(ringNamed: stamp.goal.name, dogNames: [dog.name], date: stamp.date, size: 150)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Ring Stamps")
        .navigationSubtitle(dog.name)
    }
}
