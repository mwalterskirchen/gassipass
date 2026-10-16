//
//  HomeBaseScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import CoreLocation
import SwiftUI

/// The map that sets or moves the home base of the pack. The member moves
/// the map under the pin in the middle, and a button sets the home base
/// there. The map starts at the home base or its proposal, or else follows
/// the member.
struct HomeBaseScreen: View {
    let pack: Pack
    /// Where the map starts, or nil to follow the member.
    let start: HomeBase?

    @Environment(Packs.self) private var packs
    @Environment(\.dismiss) private var dismiss
    /// The centre of the map, or nil before the map knows it.
    @State private var centre: CLLocationCoordinate2D?

    init(pack: Pack, start: HomeBase?) {
        self.pack = pack
        self.start = start
        // The map starts there, so the member can keep the place at once.
        _centre = State(initialValue: start?.coordinate)
    }

    var body: some View {
        SegmentMapView(centre: start?.coordinate, zoomLevel: 16, onMoveCentre: { centre = $0 })
            .ignoresSafeArea(edges: .bottom)
            .overlay {
                HomeBasePin()
            }
            .overlay(alignment: .top) {
                Text("Move the map so that the pin marks your home base. The rings move with it, and the ring stamps and the level stay.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(in: .rect(cornerRadius: 16))
                    .padding(8)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        guard let centre else { return }
                        try? packs.setHomeBase(HomeBase(centre), of: pack)
                        dismiss()
                    } label: {
                        Text("Set Home Base")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(centre == nil)
                    MapAttribution()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .navigationTitle("Home Base")
            .navigationBarTitleDisplayMode(.inline)
    }
}
