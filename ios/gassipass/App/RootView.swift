//
//  RootView.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import GassiPassCore
import SwiftUI

/// The tabs of the app, and what covers them: the current walk, its
/// summary, the notice of the stamps from earlier walks and an invitation.
/// It also keeps the pack up to date while the app is open.
struct RootView: View {
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
        .fullScreenCover(isPresented: .constant(walkCoversScreen)) {
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
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                comesToForeground = true
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, comesToForeground else { return }
            comesToForeground = false
            await refreshPack()
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
                await refreshPack()
            }
        }
    }

    /// Uploads what changed, also what failed to upload before, and
    /// downloads the changes of the other phones of the pack. Without an
    /// account it does neither. Then it makes the weekly goals: after the
    /// download, so that the phone takes the weekly goals of another phone
    /// of the pack when it has made them (ADR 0007).
    private func refreshPack() async {
        await account.refresh()
        await collections.makeWeeklyGoals()
    }

    /// Whether the current walk or its summary covers the tabs.
    private var walkCoversScreen: Bool {
        currentWalk.walk != nil || currentWalk.endedWalk != nil
    }

    /// Whether the notice of the stamps from earlier walks shows. It waits
    /// until no walk covers the screen.
    private var showsEarlierStamps: Binding<Bool> {
        Binding {
            collections.earlierStamps != nil && !walkCoversScreen
        } set: { isShown in
            if !isShown {
                collections.noteEarlierStampsShown()
            }
        }
    }
}
