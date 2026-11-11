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
/// goal of each dog per week, with the menu beside the title, which is
/// there while a swap is left. A retired dog gets no goals, so it shows no
/// card.
///
/// A goal with a place opens it, so that the member sees where to walk: a
/// street opens the map on the street, and a step of an area opens the
/// screen of the area.
struct GoalCard: View {
    let dog: Dog
    /// Opens the place of a goal.
    var open: (GoalPlace) -> Void = { _ in }

    @Environment(Collections.self) private var collections
    @Query(Walk.ended()) private var walks: [Walk]
    /// The slot whose swap waits for a confirmation.
    @State private var slotToSwap: Int?
    @State private var swapFailed = false

    var body: some View {
        let status = collections.goalStatus(of: dog, walks: walks.filter { $0.hasDog(dog) }, at: .now)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This Week")
                    .font(.headline)
                Spacer()
                if let status, status.canSwap {
                    swapMenu(for: status.lines.filter { $0.finishedAt == nil })
                }
            }
            if let status {
                ForEach(status.lines) { line in
                    if let place = line.goal.place, line.finishedAt == nil {
                        Button {
                            open(place)
                        } label: {
                            GoalRow(line: line, opensPlace: true)
                        }
                        // A plain button in a row of a list takes only its own taps.
                        .buttonStyle(.plain)
                        .accessibilityHint(place.hint)
                    } else {
                        GoalRow(line: line)
                    }
                }
                if status.hasWeekStamp, let date = status.goalSet.weekStampDate {
                    HStack {
                        Spacer()
                        Stamp(weekNamed: GoalText.weekName(of: status.goalSet.weekStart), dogNames: [dog.name], date: date, size: 110)
                        Spacer()
                    }
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

    /// One menu for the swap, with the goals that are not finished. It
    /// takes the place of a button on every goal.
    @ViewBuilder private func swapMenu(for lines: [GoalLine]) -> some View {
        if !lines.isEmpty {
            Menu {
                ForEach(lines) { line in
                    Button(line.title) {
                        slotToSwap = line.slot
                    }
                }
            } label: {
                Label("Swap Goal", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.iconOnly)
                    .font(.subheadline)
            }
            .tint(.secondary)
        }
    }
}

/// One weekly goal with its progress: the ring before it fills with ink,
/// and it becomes a tick when the goal is finished.
private struct GoalRow: View {
    let line: GoalLine
    /// Whether a tap opens the place of the goal, which the chevron shows.
    var opensPlace = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            GoalGauge(share: line.share, isFinished: line.finishedAt != nil)
            Text(line.title)
                .foregroundStyle(line.finishedAt == nil ? .primary : .secondary)
            Spacer()
            if line.finishedAt == nil {
                Text(line.progressText)
                    .font(.figures(.subheadline))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if opensPlace {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        // The space between the title and the progress takes taps too.
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(line.progressText)
    }
}

/// The ring before a weekly goal. Its ink grows with the progress on the
/// goal, from the top in the clockwise direction, like the outer ring of a
/// stamp. A finished goal shows the tick.
private struct GoalGauge: View {
    let share: Double
    let isFinished: Bool

    var body: some View {
        if isFinished {
            GoalCheck(isFinished: true)
        } else {
            // The hidden circle gives the ring the size and the baseline of
            // the tick, also with large text.
            Image(systemName: "circle")
                .hidden()
                .overlay {
                    ZStack {
                        Circle()
                            .stroke(.quaternary, lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: min(max(share, 0), 1))
                            .stroke(Color.forest, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .padding(1.5)
                }
                .accessibilityHidden(true)
        }
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

/// The place of a weekly goal, which a tap on the goal opens.
enum GoalPlace: Hashable {
    /// The map on the street.
    case street(Street.ID)
    /// The screen of the area.
    case area(Area.ID)

    var hint: LocalizedStringKey {
        switch self {
        case .street: "Shows the street on the map"
        case .area: "Shows the area"
        }
    }
}

extension WeeklyGoal {
    /// The place of the goal, or nil for a goal without one place.
    var place: GoalPlace? {
        switch self {
        case .street(let street?): .street(street)
        case .areaStep(let step): .area(step.area)
        case .street(nil), .newLength, .newArea, .refresh, .distance, .ring: nil
        }
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
