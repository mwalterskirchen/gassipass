//
//  WalkSummaryScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import SwiftData
import SwiftUI

/// What the walk that has just stopped earned: its distance, the new
/// segments, the length of the refreshed marks, the progress on the weekly
/// goals and the stamps of its dogs.
/// The numbers come after the update of the collections, and until then the
/// screen shows a placeholder. A button closes it. It closes by itself when
/// the walk leaves the store, for example with its pack.
struct WalkSummaryScreen: View {
    @Environment(CurrentWalk.self) private var current
    @Environment(Collections.self) private var collections
    @Query(Walk.ended()) private var walks: [Walk]

    var body: some View {
        if let walk = current.endedWalk {
            summary(of: walk, collections.summary(of: walk))
        } else {
            Color.clear
                .onAppear(perform: current.closeSummary)
        }
    }

    private func summary(of walk: Walk, _ summary: WalkSummary?) -> some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top) {
                        Figure(WalkFormat.distance(walk.distanceMetres), label: "Distance")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Figure(summary.map { $0.newSegmentCount.formatted() } ?? "–", label: "New segments",
                               alignment: .center)
                            .frame(maxWidth: .infinity)
                        Figure(summary.map { WalkFormat.distance($0.refreshedLengthMetres) } ?? "–",
                               label: "Refreshed marks", alignment: .trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                }
                if let goals = collections.goalProgress(of: walk, walks: walks), !goals.isEmpty {
                    Section("Weekly Goals") {
                        ForEach(goals) { progress in
                            GoalProgressRow(progress: progress, showsDog: Set(goals.map(\.dog)).count > 1)
                        }
                    }
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

/// The progress of a dog on a weekly goal after the walk.
private struct GoalProgressRow: View {
    let progress: WalkGoalProgress
    let showsDog: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: progress.line.finishedAt == nil ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(progress.line.finishedAt == nil ? Color.secondary : Color.forest)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.line.title)
                if showsDog {
                    Text(progress.dogName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(status)
                .font(.figures(.subheadline))
                .monospacedDigit()
                .foregroundStyle(progress.isFinishedOnWalk ? Color.forest : Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        if progress.isFinishedOnWalk {
            return String(localized: "Finished on this walk")
        }
        if progress.line.finishedAt != nil {
            return String(localized: "Finished")
        }
        if let amount = progress.line.amountMetres, let target = progress.line.goal.targetMetres {
            return GoalText.progress(amount, of: target)
        }
        return progress.line.share.formatted(.completionShare)
    }
}
