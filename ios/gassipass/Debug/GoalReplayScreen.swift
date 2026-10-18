//
//  GoalReplayScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

#if DEBUG
import SwiftData
import SwiftUI

/// The replay of the weekly goals of each dog over its last 12 weeks, as
/// text that we copy to tune the sizes of the goals (`GoalReplay`). Only
/// the debug builds have it.
struct GoalReplayScreen: View {
    @Environment(Collections.self) private var collections
    @Query(Dog.all()) private var dogs: [Dog]
    @State private var reports: [UUID: String] = [:]

    var body: some View {
        List(dogs) { dog in
            Section(dog.name) {
                if let report = reports[dog.id] {
                    Text(report)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle("Replay Weekly Goals")
        .toolbar {
            ShareLink(item: dogs.map { "\($0.name)\n\(reports[$0.id] ?? "")" }.joined(separator: "\n\n"))
        }
        .task {
            await collections.waitForUpdate()
            for dog in dogs {
                do {
                    reports[dog.id] = try await collections.goalReplay(of: dog)
                } catch {
                    reports[dog.id] = String(describing: error)
                }
            }
        }
    }
}
#endif
