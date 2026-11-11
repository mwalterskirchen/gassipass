//
//  gassipassApp.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import GassiPassCore
import OSLog
import SwiftData
import SwiftUI

@main
struct gassipassApp: App {
    private let container: ModelContainer
    private let packs: Packs
    private let account: Account
    private let currentWalk: CurrentWalk
    private let collections: Collections
    /// Nothing reads it. It stays alive to show the current walk as a Live
    /// Activity.
    private let walkActivity: WalkActivity
    private let dogChoice: DogChoice
    private let settings = AppSettings()

    private static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "App")

    init() {
        // The demo data stays in memory. It never uploads, it has no stamps
        // from earlier walks to show, and it sends no notifications.
        #if DEBUG
        let isDemo = DemoData.isOn
        #else
        let isDemo = false
        #endif
        do {
            container = isDemo ? try LocalStore.inMemory() : try LocalStore.app()
        } catch {
            fatalError("The store cannot open: \(error)")
        }
        // After the store, because the first launch carries the choice over
        // from the Core Data store.
        dogChoice = DogChoice()
        let context = container.mainContext
        #if DEBUG
        if isDemo {
            DemoData.insert(into: context)
        }
        #endif
        packs = Packs(context: context)
        // This moves the dogs from before the packs, and the demo dogs, into
        // the pack of this person.
        packs.moveDogsWithoutPack()
        account = Account(server: isDemo ? nil : SupabaseServer.ofThisBuild(), context: context)
        // Before the collections, because the distance is part of the key of
        // the stored match of a walk. A failed update tries again at the next launch.
        do {
            try Walk.updateDistances(in: context)
        } catch {
            Self.logger.error("The distances of the walks cannot update: \(String(describing: error), privacy: .public)")
        }
        let collections = Collections(
            context: context, packages: .bundled, cacheRoot: CacheFolder.folder(of: "WalkMatches"),
            defaults: isDemo ? nil : .standard, reminders: isDemo ? nil : GoalReminders(settings: settings))
        self.collections = collections
        // Update the collections at launch without waiting for a view, because
        // Core Location can launch the app in the background during a walk,
        // and the live feedback needs the collections and the areas.
        Task {
            await collections.update()
        }
        // Create the current walk at launch, so that it continues an unfinished
        // walk at once, also when Core Location launches the app in the background.
        let account = account
        currentWalk = CurrentWalk(
            context: context, collections: collections, packages: .bundled, settings: settings,
            memberName: { account.isSignedIn ? account.memberName : "" })
        walkActivity = WalkActivity(walk: currentWalk)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modifier(CollectionUpdates())
                .environment(currentWalk)
                .environment(collections)
                .environment(packs)
                .environment(account)
                .environment(dogChoice)
                .environment(settings)
                .modelContainer(container)
        }
    }
}
