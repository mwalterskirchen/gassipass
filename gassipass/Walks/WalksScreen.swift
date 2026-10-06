//
//  WalksScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreData
import SwiftUI

/// The walk list: all past walks, the newest first. A walk can be deleted
/// here, for example a walk with bad GPS. Its segments then leave the
/// collections, unless another walk of the dog also covers them.
struct WalksScreen: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Walk.ended()) private var walks
    @State private var walkToDelete: Walk?

    var body: some View {
        NavigationStack {
            List(walks) { walk in
                NavigationLink(value: walk) {
                    WalkRow(walk: walk)
                }
                // Without the destructive role, because with it the list
                // removes the row before the question is answered.
                .swipeActions {
                    Button("Delete", systemImage: "trash") { walkToDelete = walk }
                        .tint(.red)
                }
                .contextMenu {
                    Button("Delete Walk", systemImage: "trash", role: .destructive) { walkToDelete = walk }
                }
            }
            // An alert and not a confirmation dialog: on iOS 26 the dialog is a
            // popover that points at the row, and the row moves while the swipe
            // buttons close.
            .alert(
                "Delete this walk?", isPresented: Binding(
                    get: { walkToDelete != nil }, set: { if !$0 { walkToDelete = nil } }),
                presenting: walkToDelete
            ) { walk in
                Button("Cancel", role: .cancel) {}
                Button("Delete Walk", role: .destructive) {
                    context.delete(walk)
                    try? context.save()
                }
            } message: { _ in
                Text("Its segments leave the collection of each dog, unless another walk of the dog covers them. Completed records stay.")
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
        }
    }
}

private struct WalkRow: View {
    /// Observed, so that the row shows the new dogs after a change.
    @ObservedObject var walk: Walk

    @Environment(Packs.self) private var packs

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
                    Text(dogsAndMember)
                        .lineLimit(1)
                }
                .font(.figures(.subheadline, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// The dogs and the member who recorded the walk, for example "Bello
    /// with Anna", or only the dogs while the app does not know the member.
    private var dogsAndMember: String {
        guard let memberName = packs.shownMemberName(of: walk) else { return walk.dogNames }
        return String(localized: "\(walk.dogNames) with \(memberName)")
    }
}
