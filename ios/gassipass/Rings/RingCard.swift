//
//  RingCard.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import SwiftData
import SwiftUI

/// The card of the current ring of the dog at the top of the home screen:
/// the ring number, its completion, the level, and the distance from the
/// home base to the nearest new segment. A tap opens the map around the
/// home base.
///
/// A pack without a home base sees the proposal instead: the place where
/// most of its walks start, or the start of its first walk. A member
/// confirms it with one tap or moves the pin. Without a walk, the card
/// explains that the first walk gives the proposal.
struct RingCard: View {
    let pack: Pack
    let dog: Dog

    @Environment(Collections.self) private var collections
    @Environment(Packs.self) private var packs
    @Query(Walk.ended()) private var walks: [Walk]
    /// The proposal from the walks, or nil until it is known or without walks.
    @State private var proposal: HomeBase?

    var body: some View {
        if pack.homeBase != nil {
            NavigationLink {
                MapScreen(showsHomeBase: true)
                    .navigationTitle(collections.currentRing(of: dog.id)?.name ?? String(localized: "Home Base"))
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                RingRow(status: collections.ringStatus(of: dog.id), level: collections.level(of: dog.id))
            }
        } else {
            proposalView
                .task(id: walks.map(\.id)) {
                    // The first walk first, so that of two places with the
                    // same number of starts the earlier one wins.
                    proposal = await HomeBase.proposal(fromTracks: walks.reversed().compactMap(\.trackData))
                }
        }
    }

    @ViewBuilder private var proposalView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Home Base")
                .font(.headline)
            if let proposal {
                Text("Your rings start at your home base. Most of your walks start at this place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HomeBaseThumbnail(homeBase: proposal)
                HStack {
                    Button("Confirm") {
                        try? packs.setHomeBase(proposal, of: pack)
                    }
                    .buttonStyle(.glassProminent)
                    Spacer()
                    NavigationLink("Move Pin") {
                        HomeBaseScreen(pack: pack, start: proposal)
                    }
                }
            } else {
                Text("Your rings start at your home base. After your first walk, the app proposes its start.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                NavigationLink("Set on Map") {
                    HomeBaseScreen(pack: pack, start: nil)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The ring number with its completion, the level and the distance to the
/// nearest new segment. Until an update has loaded the ring, it shows grey
/// placeholders.
private struct RingRow: View {
    let status: RingStatus?
    let level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(status?.ring.name ?? "Ring 0")
                    .bigFiguresFont(size: 32)
                Spacer()
                Text(status?.completion.formattedShare ?? "00 %")
                    .font(.figures(.title3))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            CompletionBar(share: status?.completion.share ?? 0)
            HStack {
                if let nearest = status?.nearestNewSegments.first {
                    Text("Nearest new segment \(WalkFormat.distance(nearest.nearestDistanceMetres)) from the home base")
                } else {
                    Text("No new segment near the home base")
                }
                Spacer()
                if level > 0 {
                    Text("Level \(level)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .redacted(reason: status == nil ? .placeholder : [])
        .animation(.default, value: status)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A small map around the home base with a pin, which does not respond to
/// touches.
private struct HomeBaseThumbnail: View {
    let homeBase: HomeBase

    var body: some View {
        SegmentMapView(centre: homeBase.coordinate, zoomLevel: 15)
            .id(homeBase)
            .allowsHitTesting(false)
            .frame(height: 150)
            .overlay {
                HomeBasePin()
            }
            .overlay(alignment: .bottomLeading) {
                MapAttribution()
                    .padding(4)
            }
            .clipShape(.rect(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

/// The pin of the home base, whose tip marks the centre of the map.
struct HomeBasePin: View {
    var body: some View {
        Image(systemName: "mappin")
            .font(.system(size: 36, weight: .semibold))
            .foregroundStyle(Color.forest)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            // The tip of the symbol is at its bottom.
            .offset(y: -18)
            .accessibilityHidden(true)
    }
}
