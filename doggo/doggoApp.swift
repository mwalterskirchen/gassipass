//
//  doggoApp.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftData
import SwiftUI

/// Starts the app, or an empty app when the process only hosts the unit
/// tests. The unit tests make their own stores and collections, and the
/// app would open the real store, continue an unfinished walk and match
/// all walks at every test run.
@main
enum Main {
    static func main() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            UnitTestHost.main()
        } else {
            doggoApp.main()
        }
    }
}

private struct UnitTestHost: App {
    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
    }
}

struct doggoApp: App {
    private let container: ModelContainer
    private let recorder: WalkRecorder
    private let collections: Collections
    private let feedback: LiveFeedback
    private let walkActivity: WalkActivity
    private let dogChoice = DogChoice()

    init() {
        var isStoredInMemoryOnly = false
        #if DEBUG
        isStoredInMemoryOnly = DemoData.isOn
        #endif
        do {
            // CloudKit sync stays off until the models are ready for it (ticket 14).
            container = try ModelContainer(
                for: Dog.self, Walk.self, CompletedArea.self, CompletedStreet.self, PinnedArea.self,
                configurations: ModelConfiguration(
                    isStoredInMemoryOnly: isStoredInMemoryOnly, cloudKitDatabase: .none))
        } catch {
            fatalError("The store cannot open: \(error)")
        }
        #if DEBUG
        if DemoData.isOn {
            DemoData.insert(into: container.mainContext)
        }
        #endif
        let collections = Collections(
            context: container.mainContext, packageURLs: MapPackage.bundledURLs,
            cacheRoot: CacheFolder.folder(of: "WalkMatches"))
        self.collections = collections
        // Update the collections at launch without waiting for a view, because
        // Core Location can launch the app in the background during a walk,
        // and the live feedback needs the collections and the areas.
        Task {
            await collections.update()
        }
        // Create the recorder at launch, so that it continues an unfinished
        // walk at once, also when Core Location launches the app in the background.
        feedback = LiveFeedback(collections: collections)
        recorder = WalkRecorder(context: container.mainContext, feedback: feedback)
        walkActivity = WalkActivity(recorder: recorder, feedback: feedback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modifier(CollectionUpdates())
                .environment(recorder)
                .environment(feedback)
                .environment(collections)
                .environment(dogChoice)
        }
        .modelContainer(container)
    }
}

private struct RootView: View {
    @Environment(WalkRecorder.self) private var recorder

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeScreen()
            }
            Tab("Walks", systemImage: "figure.walk") {
                WalksScreen()
            }
            Tab("Dogs", systemImage: "pawprint") {
                DogsScreen()
            }
            Tab("Map", systemImage: "map") {
                MapScreen()
            }
            Tab("Book", systemImage: "book") {
                CollectionBookScreen()
            }
        }
        .fullScreenCover(isPresented: .constant(recorder.walk != nil)) {
            WalkScreen()
        }
    }
}
