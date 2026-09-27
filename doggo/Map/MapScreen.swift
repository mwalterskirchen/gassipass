//
//  MapScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// Shows the segments of the bundled map packages on the swisstopo base map,
/// and the track of a walk if there is one.
struct MapScreen: View {
    var track: Track?

    @State private var loadResult: Result<[MapPackage], any Error>?

    var body: some View {
        Group {
            switch loadResult {
            case .success(let packages):
                SegmentMapView(packages: packages, track: track?.coordinates ?? [])
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        MapAttribution()
                            .padding(.horizontal)
                            .padding(.bottom, 4)
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
}

#Preview {
    MapScreen()
}
