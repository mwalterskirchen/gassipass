//
//  gassipassApp.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreData
import OSLog
import SwiftUI

/// Starts the app, or an empty app when the process only hosts the unit
/// tests. The unit tests make their own stores and collections, and the
/// app would open the real store, continue an unfinished walk and match
/// all walks at every test run.
@main
enum Main {
    static func main() {
        #if DEBUG
        // With `-initializeCloudKitSchema YES`, the app only writes the
        // CloudKit schema, prints the result and quits.
        if UserDefaults.standard.bool(forKey: "initializeCloudKitSchema") {
            do {
                try Stores.initializeCloudKitSchema()
                print("The CloudKit schema is initialized.")
            } catch {
                print("The CloudKit schema cannot initialize: \(error)")
            }
            exit(0)
        }
        #endif
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            UnitTestHost.main()
        } else {
            gassipassApp.main()
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

struct gassipassApp: App {
    private let stores: Stores
    private let packs: Packs
    private let currentWalk: CurrentWalk
    private let collections: Collections
    private let walkActivity: WalkActivity
    private let dogChoice = DogChoice()
    private let settings = AppSettings()

    private static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "App")

    init() {
        var isStoredInMemoryOnly = false
        #if DEBUG
        isStoredInMemoryOnly = DemoData.isOn
        #endif
        do {
            // The demo data never syncs.
            stores = isStoredInMemoryOnly ? try Stores.inMemory() : try Stores.app()
        } catch {
            fatalError("The store cannot open: \(error)")
        }
        let context = stores.container.viewContext
        #if DEBUG
        if DemoData.isOn {
            DemoData.insert(into: context)
        }
        #endif
        packs = Packs(stores: stores)
        // At the first launch of the build with packs, this moves all dogs
        // into the own pack of this person.
        packs.tidyUp()
        // Before the collections, because the distance is part of the key of
        // the stored match of a walk. A failed update tries again at the next launch.
        do {
            try Walk.updateDistances(in: context)
        } catch {
            Self.logger.error("The distances of the walks cannot update: \(String(describing: error), privacy: .public)")
        }
        let collections = Collections(
            context: context, packages: .bundled, cacheRoot: CacheFolder.folder(of: "WalkMatches"))
        self.collections = collections
        // Update the collections at launch without waiting for a view, because
        // Core Location can launch the app in the background during a walk,
        // and the live feedback needs the collections and the areas.
        Task {
            await collections.update()
        }
        // Create the current walk at launch, so that it continues an unfinished
        // walk at once, also when Core Location launches the app in the background.
        currentWalk = CurrentWalk(
            context: context, collections: collections, packages: .bundled, settings: settings)
        walkActivity = WalkActivity(walk: currentWalk)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modifier(CollectionUpdates())
                .modifier(PackUpdates())
                .environment(currentWalk)
                .environment(collections)
                .environment(packs)
                .environment(dogChoice)
                .environment(settings)
                .environment(\.managedObjectContext, stores.container.viewContext)
        }
    }
}

private struct RootView: View {
    @Environment(CurrentWalk.self) private var currentWalk

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
        .fullScreenCover(isPresented: .constant(currentWalk.walk != nil)) {
            WalkScreen()
        }
    }
}
