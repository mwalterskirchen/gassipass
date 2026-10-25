//
//  EarlierStampsSheet.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import SwiftData
import SwiftUI

/// The notice at the first start after the app got the steps of the area
/// stamps: how many new stamps each dog got from its earlier walks. The app
/// shows it once (`Collections.earlierStamps`).
struct EarlierStampsSheet: View {
    @Environment(Collections.self) private var collections
    @Environment(\.dismiss) private var dismiss
    @Query(Dog.all()) private var dogs: [Dog]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("An area now gets an entry stamp with its first segment, and its round stamp grows at a quarter, a half and three quarters. The area counts as completed at 95 percent. Your earlier walks have earned these stamps, with the dates of those walks.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(dogs.filter { counts[$0.id] != nil }) { dog in
                        HStack(spacing: 12) {
                            DogBadge(dog: dog, size: 36)
                            Text(dog.name)
                            Spacer()
                            Text("\(counts[dog.id] ?? 0) new stamps")
                                .monospacedDigit()
                                .foregroundStyle(Color.stampInk)
                                .fontWeight(.semibold)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("New stamps")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var counts: [UUID: Int] {
        collections.earlierStamps ?? [:]
    }
}
