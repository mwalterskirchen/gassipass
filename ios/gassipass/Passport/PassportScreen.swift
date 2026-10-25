//
//  PassportScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// The passport: the identity page of one dog, and all areas of a canton
/// for the dog, including areas with no completion yet. Each area shows its completion, the date if the
/// dog has completed it, and a small map that the dog's collected segments
/// fill in. An area opens its area screen. The rows above the areas open the
/// page with the ring stamps of the dog, and a page for each year with its
/// weeks and week stamps.
///
/// The dog picker lists every dog, so that the book of a retired dog stays
/// open.
struct PassportScreen: View {
    @Environment(Collections.self) private var collections
    @Environment(DogChoice.self) private var dogChoice
    @Query(Dog.all()) private var dogs: [Dog]
    @Query(Walk.ended()) private var walks: [Walk]
    @State private var chosenCanton: String?
    @AppStorage(OrderMenu.key) private var order: Passport.Order = OrderMenu.defaultOrder

    var body: some View {
        NavigationStack {
            Group {
                if dogs.isEmpty {
                    ContentUnavailableView(
                        "No Dogs", systemImage: "pawprint",
                        description: Text("Add a dog to start its passport."))
                } else if collections.areas.isEmpty {
                    ProgressView()
                } else {
                    book
                }
            }
            .navigationTitle("Passport")
            .toolbar {
                if !dogs.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        OrderMenu()
                    }
                }
                if dogs.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        DogPicker(dogs: dogs)
                    }
                }
            }
            .navigationDestination(for: Area.ID.self) { areaID in
                if let area = collections.areas[areaID] {
                    AreaScreen(area: area, dog: shownDog, collections: collections)
                }
            }
        }
    }

    private var book: some View {
        let pages = pages
        return List {
            if let dog = shownDog {
                Section {
                    IdentityPage(identity: PassportIdentity(dog: dog, now: .now), photo: dog.photoData)
                }
            }
            Section {
                Picker("Canton", selection: Binding(get: { shownCanton }, set: { chosenCanton = $0 })) {
                    ForEach(collections.cantons, id: \.self) { canton in
                        Text("Canton \(canton)").tag(Optional(canton))
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if let dog = shownDog {
                Section {
                    NavigationLink {
                        RingStampsScreen(dog: dog)
                    } label: {
                        LabeledContent("Ring Stamps", value: collections.ringRecords(of: dog.id).count.formatted())
                    }
                    ForEach(years(of: dog), id: \.self) { year in
                        NavigationLink {
                            YearScreen(dog: dog, year: year)
                        } label: {
                            LabeledContent(String(year), value: String(localized: "\(weekStamps(of: dog, in: year)) week stamps"))
                        }
                    }
                }
            }
            Section {
                ForEach(pages) { page in
                    NavigationLink(value: page.id) {
                        PageRow(page: page)
                    }
                }
            } header: {
                Text("\(pages.count { $0.completedAt != nil }) of \(pages.count) completed")
            }
        }
        // Another dog is new content, so its completions do not roll in.
        .id(shownDog?.id)
    }

    private var shownDog: Dog? {
        dogChoice.shownDog(in: dogs)
    }

    /// The years of the weeks of the dog, the newest first: from the year
    /// of its first walk or set of weekly goals to this year.
    private func years(of dog: Dog) -> [Int] {
        let calendar = WeekCalendar.calendar
        let first = (walks.filter { $0.hasDog(dog) }.map(\.startedAt) + collections.goalSets(of: dog.id).map(\.weekStart))
            .min() ?? .now
        let from = calendar.component(.yearForWeekOfYear, from: first)
        let to = calendar.component(.yearForWeekOfYear, from: .now)
        return Array((from...max(from, to)).reversed())
    }

    private func weekStamps(of dog: Dog, in year: Int) -> Int {
        collections.goalSets(of: dog.id).count {
            $0.hasWeekStamp && WeekCalendar.calendar.component(.yearForWeekOfYear, from: $0.weekStart) == year
        }
    }

    /// The canton that the screen shows when the dog has collected nothing
    /// yet: canton Zürich, where the first test area Dietikon lies.
    private static let fallbackCanton = "ZH"

    /// The canton that the screen shows: the chosen canton, else the canton
    /// where the dog has collected the most segments, else the fallback.
    private var shownCanton: String? {
        if let chosenCanton { return chosenCanton }
        if let canton = collections.cantonWithMostCollected(by: shownDog?.id) { return canton }
        let cantons = collections.cantons
        return cantons.contains(Self.fallbackCanton) ? Self.fallbackCanton : cantons.first
    }

    private var pages: [Passport.Page] {
        guard let shownCanton, let dog = shownDog else { return [] }
        return Passport.sorted(collections.pages(canton: shownCanton, for: dog), by: order)
    }
}

#Preview {
    PassportScreen()
        .environment(Collections.preview())
        .environment(DogChoice())
        .modelContainer(.preview)
}
