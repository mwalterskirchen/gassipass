//
//  DistanceScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 15.10.2026.
//

import SwiftData
import SwiftUI

/// The distance that one dog walked: a chart with a bar for each day of a
/// week, for each of 12 weeks, or for each month of a year, and the totals
/// of all walks of the dog.
///
/// The arrows show the page before or after. A tap on a bar shows the
/// distance and the walks of that bar in place of the total of the page.
/// The longest walk opens its detail screen.
struct DistanceScreen: View {
    let dog: Dog
    @Query(Walk.ended()) private var walks: [Walk]
    @State private var unit = DistanceUnit.day
    /// A date on the shown page.
    @State private var shownDate = Date.now
    @State private var selection: Date?

    var body: some View {
        let dogWalks = walks.filter { $0.hasDog(dog) }
        let distance = DogDistance(dogWalks)
        let page = distance.page(unit, containing: shownDate)
        List {
            if !dogWalks.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 20) {
                        Picker("Period", selection: $unit) {
                            Text("Days").tag(DistanceUnit.day)
                            Text("Weeks").tag(DistanceUnit.week)
                            Text("Months").tag(DistanceUnit.month)
                        }
                        .pickerStyle(.segmented)
                        headline(of: page)
                        DistanceChart(page: page, selection: $selection)
                    }
                    .padding(.vertical, 8)
                    .animatesChange(of: page)
                }
                Section("All Walks") {
                    allWalks(distance, dogWalks: dogWalks)
                }
            }
        }
        .overlay {
            if dogWalks.isEmpty {
                ContentUnavailableView(
                    "No Walks", systemImage: "figure.walk",
                    description: Text("Start a walk to see how far \(dog.name) walks."))
            }
        }
        .navigationTitle("Distance")
        .navigationSubtitle(dog.name)
        .onChange(of: unit) { selection = nil }
        .onChange(of: shownDate) { selection = nil }
    }

    /// The distance of the page or of the selected bar, what it covers, and
    /// the average or the number of walks. The arrows move to the page
    /// before or after.
    private func headline(of page: DistancePage) -> some View {
        let bar = selection.flatMap(page.bar(containing:))
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(WalkFormat.distance(bar?.metres ?? page.metres))
                    .monospacedDigit()
                    .bigFiguresFont(size: 48)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text(bar.map { DistanceFormat.barTitle(of: $0, unit: page.unit) } ?? title(of: page))
                    .font(.subheadline.weight(.semibold))
                Text(bar.map(walkCount(of:)) ?? average(of: page))
                    .font(.figures(.subheadline, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            HStack(spacing: 8) {
                Button("Earlier", systemImage: "chevron.left") {
                    shownDate = unit.date(shownDate, movedBy: -1, calendar: WeekCalendar.calendar)
                }
                .disabled(!page.hasEarlier)
                Button("Later", systemImage: "chevron.right") {
                    shownDate = unit.date(shownDate, movedBy: 1, calendar: WeekCalendar.calendar)
                }
                .disabled(!page.hasLater)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
        }
    }

    /// The days that the page covers, for example "This week" or
    /// "28 Sep – 4 Oct 2026".
    private func title(of page: DistancePage) -> String {
        let now = DistanceUnit.day.page(containing: .now, calendar: WeekCalendar.calendar)
        switch page.unit {
        case .day where page.interval == now:
            return String(localized: "This week")
        case .day where page.interval.end == now.start:
            return String(localized: "Last week")
        case .week where page.interval.end == now.end:
            return String(localized: "Last 12 weeks")
        case .day, .week:
            return DistanceFormat.days(of: page.interval)
        case .month:
            return page.interval.start.formatted(.dateTime.year())
        }
    }

    private func average(of page: DistancePage) -> String {
        guard let metres = page.averageMetres else { return String(localized: "No walks") }
        let average = WalkFormat.distance(metres)
        return switch page.unit {
        case .day: String(localized: "\(average) per day on average")
        case .week: String(localized: "\(average) per week on average")
        case .month: String(localized: "\(average) per month on average")
        }
    }

    private func walkCount(of bar: DistanceBar) -> String {
        bar.walkMetres.isEmpty ? String(localized: "No walks") : String(localized: "\(bar.walkMetres.count) walks")
    }

    @ViewBuilder private func allWalks(_ distance: DogDistance, dogWalks: [Walk]) -> some View {
        LabeledContent("Total distance", value: WalkFormat.distance(distance.totalMetres))
        LabeledContent("Walks", value: distance.walks.count.formatted())
        if let average = distance.averageWalkMetres {
            LabeledContent("Average walk", value: WalkFormat.distance(average))
        }
        if let longest = distance.longestWalk, let walk = dogWalks.first(where: { $0.id == longest.id }) {
            NavigationLink(value: walk) {
                LabeledContent {
                    Text(WalkFormat.distance(longest.distanceMetres))
                } label: {
                    Text("Longest walk")
                    Text(WalkFormat.relativeDay(longest.startedAt))
                }
            }
        }
        if let first = distance.walks.first {
            LabeledContent("First walk", value: WalkFormat.relativeDay(first.startedAt))
        }
    }
}

#Preview {
    NavigationStack {
        DistanceScreen(dog: Dog(name: "Bello", context: .preview))
    }
    .modelContainer(.preview)
}
