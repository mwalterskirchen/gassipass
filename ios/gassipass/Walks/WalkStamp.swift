//
//  WalkStamp.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import SwiftUI

/// The stamp that dogs earned on a walk, on the map of the walk and in its
/// summary: the round stamp of a street, the entry stamp of an area, the
/// round stamp of an area at its step, the ring stamp or the week stamp. A
/// finished weekly goal shows as a tick, because the passport keeps only
/// the week stamp.
struct WalkStamp: View {
    let goal: CurrentWalk.CompletedGoal
    /// The diameter of a round stamp, in points.
    let size: CGFloat

    var body: some View {
        switch goal.id {
        case .area(_, .entry):
            EntryStamp(name: goal.name, date: goal.date, scale: size / 70)
        case .area(let area, let step):
            Stamp(area: area, name: goal.name, dogNames: goal.dogNames, date: goal.date, size: size, step: step)
        case .street:
            Stamp(name: goal.name, dogNames: goal.dogNames, date: goal.date, size: size * 0.9) {
                Image(systemName: "pawprint.fill")
                    .resizable()
                    .scaledToFit()
            }
        case .ring:
            Stamp(ringNamed: goal.name, dogNames: goal.dogNames, date: goal.date, size: size)
        case .weekStamp:
            Stamp(weekNamed: goal.name, dogNames: goal.dogNames, date: goal.date, size: size)
        case .weeklyGoal:
            GoalTick(name: goal.name, size: size)
        }
    }
}

extension CurrentWalk.CompletedGoal {
    /// Whether the stamp is the entry stamp of an area, which is not round.
    var isEntryStamp: Bool {
        if case .area(_, .entry) = id { true } else { false }
    }

    /// What the dogs earned, in a few words.
    var caption: LocalizedStringResource {
        switch id {
        case .area(_, .entry): "Entry stamp"
        case .area(_, .completed): "Area completed"
        case .area(_, let step): "\(step.inkedShare.formatted(.percent)) of the area"
        case .street: "Street completed"
        case .ring: "Ring completed"
        case .weeklyGoal: "Weekly goal finished"
        case .weekStamp: "Week stamp"
        }
    }
}

/// A finished weekly goal: a tick with the goal in words, in the size of a
/// round stamp, but without its ink and its ring.
private struct GoalTick: View {
    let name: String
    let size: CGFloat

    var body: some View {
        VStack(spacing: size * 0.04) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.4)
                .foregroundStyle(Color.forest)
            Text(name)
                .font(.system(size: size * 0.08, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .frame(width: size * 0.7)
        }
        .frame(width: size, height: size)
    }
}
