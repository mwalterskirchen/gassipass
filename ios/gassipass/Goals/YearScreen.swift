//
//  YearScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import SwiftData
import SwiftUI

/// The page of the collection book with the weeks of one year for one dog:
/// each week with a week stamp, a tick for one or two finished goals, a dash
/// for a week without a walk, which pauses the streak, or nothing. The week
/// stamps of the year show above the weeks.
struct YearScreen: View {
    let dog: Dog
    let year: Int

    @Environment(Collections.self) private var collections
    @Query(Walk.ended()) private var walks: [Walk]

    var body: some View {
        let sets = collections.goalSets(of: dog.id)
        let weeks = WeeklyGoals.weeks(
            ofYear: year, sets: sets, walks: collections.goalWalks(of: dog.id, in: walks), now: .now)
        let stamps = sets
            .filter { set in weeks.contains { $0.weekStart.isSameMillisecond(as: set.weekStart) } }
            .compactMap { set in set.weekStampDate.map { (weekStart: set.weekStart, date: $0) } }
            .sorted { $0.weekStart < $1.weekStart }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !stamps.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], spacing: 16) {
                        ForEach(stamps, id: \.weekStart) { stamp in
                            Stamp(
                                weekNamed: GoalText.weekName(of: stamp.weekStart), dogNames: [dog.name],
                                date: stamp.date, size: 120)
                        }
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 12) {
                    ForEach(weeks) { week in
                        WeekCell(week: week)
                    }
                }
                Text("A week stamp is three finished goals, a tick is one or two, and a dash is a week without a walk, which pauses the streak.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .navigationTitle(String(year))
        .navigationSubtitle(dog.name)
    }
}

/// One week of the year page: its number and its mark.
private struct WeekCell: View {
    let week: YearWeek

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                switch week.mark {
                case .weekStamp:
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.stampInk)
                case .finishedGoals:
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.forest)
                case .paused:
                    Image(systemName: "minus")
                        .foregroundStyle(.secondary)
                case .none:
                    Circle()
                        .strokeBorder(.quaternary, lineWidth: 1)
                        .frame(width: 18, height: 18)
                }
            }
            .font(.title3.weight(.semibold))
            .frame(height: 28)
            Text(WeekCalendar.calendar.component(.weekOfYear, from: week.weekStart).formatted())
                .font(.figures(.caption2))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(GoalText.weekName(of: week.weekStart)))
        .accessibilityValue(Text(markText))
    }

    private var markText: LocalizedStringResource {
        switch week.mark {
        case .weekStamp: "Week stamp"
        case .finishedGoals: "Goals finished"
        case .paused: "No walk"
        case .none: "Nothing"
        }
    }
}
