//
//  GoalCard.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

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
        .confirmationDialog("Swap this goal?", isPresented: isConfirming, titleVisibility: .visible) {
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

    private var isConfirming: Binding<Bool> {
        Binding { slotToSwap != nil } set: { if !$0 { slotToSwap = nil } }
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
                Image(systemName: line.finishedAt == nil ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(line.finishedAt == nil ? Color.secondary : Color.forest)
                    .accessibilityHidden(true)
                Text(line.title)
                Spacer()
                Text(progressText)
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
        .accessibilityValue(line.finishedAt == nil ? progressText : String(localized: "Finished"))
    }

    private var progressText: String {
        if line.finishedAt != nil {
            return String(localized: "Finished")
        }
        if let amount = line.amountMetres, let target = line.goal.targetMetres {
            return GoalText.progress(amount, of: target)
        }
        return line.share.formatted(.completionShare)
    }
}
