//
//  doggoApp.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

@main
struct doggoApp: App {
    private let container: ModelContainer
    private let recorder: WalkRecorder

    init() {
        do {
            // CloudKit sync stays off until the models are ready for it (ticket 14).
            container = try ModelContainer(
                for: Dog.self, Walk.self,
                configurations: ModelConfiguration(cloudKitDatabase: .none))
        } catch {
            fatalError("The store cannot open: \(error)")
        }
        // Create the recorder at launch, so that it continues an unfinished
        // walk at once, also when Core Location launches the app in the background.
        recorder = WalkRecorder(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(recorder)
        }
        .modelContainer(container)
    }
}

private struct RootView: View {
    @Environment(WalkRecorder.self) private var recorder

    var body: some View {
        TabView {
            Tab("Walks", systemImage: "figure.walk") {
                WalksScreen()
            }
            Tab("Dogs", systemImage: "pawprint") {
                DogsScreen()
            }
            Tab("Map", systemImage: "map") {
                MapScreen()
            }
        }
        .fullScreenCover(isPresented: .constant(recorder.walk != nil)) {
            WalkScreen()
        }
    }
}
