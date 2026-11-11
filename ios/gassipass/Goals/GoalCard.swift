//
//  GoalCard.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import GassiPassCore
import SwiftData
import SwiftUI

/// The card of the weekly goals of the dog at the top of the home screen:
/// the three goals of this week with the progress on each, and the week
/// stamp when the dog has finished all three. A member can swap one
/// goal of each dog per week. A retired dog gets no goals, so it shows no
/// card.
struct GoalCard: View {
    let dog: Dog

    @Environment(Collections.self) private var collections
    @Query(Walk.ended()) private var walks: [Walk]
    /// The slot whose swap waits for a confirmation.
    @State private var slotToSwap: Int?
    @State private var swapFailed = false

    var body: some View {
        let status = collections.goalStatus(of: dog, walks: walks.filter { $0.hasDog(dog) }, at: .now)
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)
            if let status {
                ForEach(status.lines) { line in
                    GoalRow(line: line, canSwap: status.canSwap) {
                        slotToSwap = line.slot
                    }
                }
                if status.hasWeekStamp, let date = status.goalSet.weekStampDate {
                    HStack {
                        Spacer()
                        Stamp(weekNamed: GoalText.weekName(of: status.goalSet.weekStart), dogNames: [dog.name], date: date, size: 110)
                        Spacer()
                    }
                } else if !status.canSwap {
                    Text("Each dog can swap one goal per week.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("The goals of this week appear soon.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .animation(.default, value: status)
        .confirmationDialog("Swap this goal?", isPresented: Binding(isPresent: $slotToSwap), titleVisibility: .visible) {
            Button("Swap Goal") {
                if let slotToSwap {
                    swapFailed = !collections.swapGoal(inSlot: slotToSwap, of: dog)
                }
            }
        } message: {
            Text("Each dog can swap one goal per week.")
        }
        .alert("No other goal fits this week.", isPresented: $swapFailed) {}
    }
}

/// One weekly goal with its progress, and its swap button.
private struct GoalRow: View {
    let line: GoalLine
    let canSwap: Bool
    let swap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                GoalCheck(isFinished: line.finishedAt != nil)
                Text(line.title)
                Spacer()
                Text(line.progressText)
                    .font(.figures(.subheadline))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if canSwap, line.finishedAt == nil {
                    Button("Swap", systemImage: "arrow.triangle.2.circlepath", action: swap)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }
            if line.finishedAt == nil {
                CompletionBar(share: line.share)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(line.progressText)
    }
}

/// The circle before a weekly goal, with a tick when the goal is finished.
struct GoalCheck: View {
    let isFinished: Bool

    var body: some View {
        Image(systemName: isFinished ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isFinished ? Color.forest : Color.secondary)
            .accessibilityHidden(true)
    }
}

extension GoalLine {
    /// The progress on the goal: "Finished", the length of its target that
    /// the dog has, or its share.
    var progressText: String {
        if finishedAt != nil {
            return String(localized: "Finished")
        }
        if let amount = amountMetres, let target = goal.targetMetres {
            return GoalText.progress(amount, of: target)
        }
        return share.formatted(.completionShare)
    }
}
