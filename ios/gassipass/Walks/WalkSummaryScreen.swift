//
//  WalkSummaryScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import SwiftUI

/// What the walk that has just stopped earned: its distance, the new
/// segments and the stamps of its dogs. The numbers come after the update of
/// the collections, and until then the screen shows a placeholder. A button
/// closes it.
struct WalkSummaryScreen: View {
    let walk: Walk
    @Environment(CurrentWalk.self) private var current
    @Environment(Collections.self) private var collections

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top) {
                        Figure(WalkFormat.distance(walk.distanceMetres), label: "Distance")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Figure(summary.map { $0.newSegmentCount.formatted() } ?? "–", label: "New segments",
                               alignment: .trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                }
                Section("Stamps") {
                    if let summary {
                        if summary.stamps.isEmpty {
                            Text("No new stamps on this walk.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(summary.stamps) { stamp in
                            StampRow(stamp: stamp)
                        }
                    } else {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Counting what the walk earned…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .animation(.default, value: summary)
            .navigationTitle(walk.dogNames)
            .navigationSubtitle("Walk ended")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: current.closeSummary) {
                    Text("Close")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(20)
            }
        }
    }

    private var summary: WalkSummary? {
        collections.summary(of: walk)
    }
}

/// One stamp of the walk, with what it is for and the dogs that earned it.
private struct StampRow: View {
    let stamp: CurrentWalk.CompletedGoal

    var body: some View {
        HStack(spacing: 16) {
            WalkStamp(goal: stamp, size: 72)
                .frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 2) {
                Text(stamp.name)
                    .font(.headline)
                Text(stamp.caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(stamp.dogNames.formatted(.list(type: .and)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
