//
//  WalksScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// The walk list: all past walks, the newest first.
struct WalksScreen: View {
    @Query(filter: #Predicate<Walk> { $0.endedAt != nil }, sort: \Walk.startedAt, order: .reverse)
    private var walks: [Walk]
    @State private var isStartingWalk = false

    var body: some View {
        NavigationStack {
            List(walks) { walk in
                NavigationLink(value: walk) {
                    WalkRow(walk: walk)
                }
            }
            .overlay {
                if walks.isEmpty {
                    ContentUnavailableView(
                        "No Walks", systemImage: "figure.walk",
                        description: Text("Your walks appear here."))
                }
            }
            .navigationTitle("Walks")
            .navigationDestination(for: Walk.self) { walk in
                WalkDetailScreen(walk: walk)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isStartingWalk = true
                } label: {
                    Label("Start Walk", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .sheet(isPresented: $isStartingWalk) {
                StartWalkSheet()
            }
        }
    }
}

private struct WalkRow: View {
    let walk: Walk

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(WalkFormat.date(walk.startedAt))
                .font(.headline)
            HStack(spacing: 12) {
                WalkStats(walk: walk)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
