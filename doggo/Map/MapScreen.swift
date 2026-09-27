//
//  MapScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// Shows the segments of the bundled map package on the swisstopo base map.
struct MapScreen: View {
    static let packageURL = Bundle.main.url(forResource: "dietikon", withExtension: "sqlite")!

    @State private var loadResult: Result<[Segment], any Error>?

    var body: some View {
        Group {
            switch loadResult {
            case .success(let segments):
                SegmentMapView(segments: segments)
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
            loadResult = Result { try MapPackage(url: Self.packageURL).segments() }
        }
    }
}

#Preview {
    MapScreen()
}
