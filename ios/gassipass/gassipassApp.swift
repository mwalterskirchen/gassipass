//
//  gassipassApp.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import OSLog
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
    private let container: ModelContainer
    private let packs: Packs
    private let account: Account
    private let currentWalk: CurrentWalk
    private let collections: Collections
    private let walkActivity: WalkActivity
    /// Made after the store, because the first launch carries the choice
    /// over from the Core Data store.
    private let dogChoice: DogChoice
    private let settings = AppSettings()

    private static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "App")

    init() {
        var isStoredInMemoryOnly = false
        #if DEBUG
        isStoredInMemoryOnly = DemoData.isOn
        #endif
        do {
            container = isStoredInMemoryOnly ? try LocalStore.inMemory() : try LocalStore.app()
        } catch {
            fatalError("The store cannot open: \(error)")
        }
        dogChoice = DogChoice()
        let context = container.mainContext
        #if DEBUG
        if DemoData.isOn {
            DemoData.insert(into: context)
        }
        #endif
        packs = Packs(context: context)
        // This moves the dogs from before the packs, and the demo dogs, into
        // the pack of this person.
        packs.moveDogsWithoutPack()
        // The demo data never uploads.
        var server: SupabaseServer? = SupabaseServer.ofThisBuild()
        #if DEBUG
        if DemoData.isOn {
            server = nil
        }
        #endif
        account = Account(server: server, context: context)
        // Before the collections, because the distance is part of the key of
        // the stored match of a walk. A failed update tries again at the next launch.
        do {
            try Walk.updateDistances(in: context)
        } catch {
            Self.logger.error("The distances of the walks cannot update: \(String(describing: error), privacy: .public)")
        }
        // The demo data has no stamps from earlier walks to show, and sends
        // no notifications.
        var defaults: UserDefaults? = .standard
        var reminders: GoalReminders? = GoalReminders(settings: settings)
        #if DEBUG
        if DemoData.isOn {
            defaults = nil
            reminders = nil
        }
        #endif
        let collections = Collections(
            context: context, packages: .bundled, cacheRoot: CacheFolder.folder(of: "WalkMatches"),
            defaults: defaults, reminders: reminders)
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

private struct RootView: View {
    @Environment(CurrentWalk.self) private var currentWalk
    @Environment(Collections.self) private var collections
    @Environment(Account.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    /// Whether the app comes to the foreground: at the launch, and after it
    /// was in the background. Control Center or an alert makes the app
    /// inactive for a moment, and it stays in the foreground.
    @State private var comesToForeground = true

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
            Tab("Passport", systemImage: "book.closed") {
                PassportScreen()
            }
        }
        // A stopped walk ends on its summary.
        .fullScreenCover(isPresented: .constant(currentWalk.walk != nil || currentWalk.endedWalk != nil)) {
            if currentWalk.walk == nil {
                WalkSummaryScreen()
            } else {
                WalkScreen()
            }
        }
        .sheet(isPresented: showsEarlierStamps) {
            EarlierStampsSheet()
        }
        .opensInvitations()
        // Uploads what changed, also what failed to upload before, and
        // downloads the changes of the other phones of the pack. Without an
        // account it does nothing.
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                comesToForeground = true
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, comesToForeground else { return }
            comesToForeground = false
            await account.refresh()
            // After the download, so that the phone takes the weekly goals of
            // another phone of the pack when it has made them (ADR 0007).
            await collections.makeWeeklyGoals()
        }
        .task {
            await account.uploadChanges(whenConnected: NetworkConnections.stream())
        }
        // A phone that stays open across Monday midnight makes the weekly
        // goals of the new week too.
        .task {
            while !Task.isCancelled {
                let start = WeekCalendar.week(containing: .now).end
                try? await Task.sleep(for: .seconds(max(start.timeIntervalSinceNow, 1)))
                guard !Task.isCancelled, Date.now >= start else { continue }
                await account.refresh()
                await collections.makeWeeklyGoals()
            }
        }
    }

    /// Whether the notice of the stamps from earlier walks shows. It waits
    /// until no walk covers the screen.
    private var showsEarlierStamps: Binding<Bool> {
        Binding {
            collections.earlierStamps != nil && currentWalk.walk == nil && currentWalk.endedWalk == nil
        } set: { isShown in
            if !isShown {
                collections.noteEarlierStampsShown()
            }
        }
    }
}
