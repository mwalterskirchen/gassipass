//
//  WalksScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// The walk list: all past walks, the newest first. A walk can be deleted
/// here, for example a walk with bad GPS. Its segments then leave the
/// collections, unless another walk of the dog also covers them.
struct WalksScreen: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Walk> { $0.endedAt != nil }, sort: \Walk.startedAt, order: .reverse)
    private var walks: [Walk]
    @State private var walkToDelete: Walk?

    var body: some View {
        NavigationStack {
            List(walks) { walk in
                NavigationLink(value: walk) {
                    WalkRow(walk: walk)
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { walkToDelete = walk }
                }
                .contextMenu {
                    Button("Delete Walk", systemImage: "trash", role: .destructive) { walkToDelete = walk }
                }
            }
            .confirmationDialog(
                "Delete this walk?", isPresented: Binding(
                    get: { walkToDelete != nil }, set: { if !$0 { walkToDelete = nil } }),
                titleVisibility: .visible, presenting: walkToDelete
            ) { walk in
                Button("Delete Walk", role: .destructive) {
                    context.delete(walk)
                    try? context.save()
                }
            } message: { _ in
                Text("Its segments leave the collection of each dog, unless another walk of the dog covers them. Completed records stay.")
            }
            .overlay {
                if walks.isEmpty {
                    MascotUnavailableView("No Walks", description: "Your walks appear here.")
                }
            }
            .navigationTitle("Walks")
            .navigationDestination(for: Walk.self) { walk in
                WalkDetailScreen(walk: walk)
            }
        }
    }
}

private struct WalkRow: View {
    let walk: Walk

    var body: some View {
        HStack(spacing: 14) {
            TrackThumbnail(walk: walk)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(WalkFormat.day(walk.startedAt))
                        .font(.headline)
                    Spacer()
                    Text(walk.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                // Without the icons of the walk detail, so that the line fits
                // beside the drawing of the track.
                HStack(spacing: 12) {
                    Text(WalkFormat.distance(walk.distanceMetres))
                    Text(WalkFormat.duration(walk.duration))
                    Text(walk.dogNames)
                        .lineLimit(1)
                }
                .font(.figures(.subheadline, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
