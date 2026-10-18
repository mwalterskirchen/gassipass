//
//  SettingsScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import SwiftData
import SwiftUI
import UserNotifications

/// The settings of the app, which the gear button on the home screen opens.
/// The home screen pushes it, because a sixth tab makes iOS hide tabs
/// behind "More". A change counts at once, so the screen has no Save button.
struct SettingsScreen: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Account.self) private var account
    @Environment(Collections.self) private var collections
    @Query(Pack.all()) private var packs: [Pack]

    var body: some View {
        @Bindable var settings = settings
        List {
            AccountSection()
            if packs.isEmpty {
                Section("Pack") {
                    Text("Your pack starts when you add your first dog.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(packs) { pack in
                Section {
                    PackNameField(pack: pack)
                    NavigationLink {
                        HomeBaseScreen(pack: pack, start: pack.homeBase)
                    } label: {
                        LabeledContent("Home Base", value: pack.homeBase == nil
                            ? String(localized: "Not set") : String(localized: "Set"))
                    }
                    PackMemberRows(pack: pack)
                } header: {
                    Text("Pack")
                } footer: {
                    if account.isPackOwner {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("An invitation is a link for one person. It works once and expires after 7 days.")
                            if account.packMembers.count > 1 {
                                Text("To remove a member, swipe their row to the left.")
                            }
                        }
                    }
                }
            }
            Section {
                Toggle("Vibrate for Collected Segments", isOn: $settings.vibratesForCollectedSegments)
            } footer: {
                Text("The phone vibrates during a walk when a segment becomes collected.")
            }
            Section {
                Toggle("New Weekly Goals", isOn: $settings.notifiesAboutNewGoals)
                Toggle("One More Goal", isOn: $settings.notifiesAboutLastGoal)
            } header: {
                Text("Notifications")
            } footer: {
                Text("On Monday at 8:00 the phone tells you about the new weekly goals. On Sunday at 17:00 it names the goal that is left when a week stamp needs one more goal.")
            }
            #if DEBUG
            Section("Debug") {
                NavigationLink("Replay Weekly Goals") {
                    GoalReplayScreen()
                }
            }
            #endif
        }
        .navigationTitle("Settings")
        .onChange(of: settings.notifiesAboutNewGoals) { _, isOn in notificationsChanged(isOn: isOn) }
        .onChange(of: settings.notifiesAboutLastGoal) { _, isOn in notificationsChanged(isOn: isOn) }
        // The new members of the pack show after a refresh.
        .refreshesPack()
    }
}

extension SettingsScreen {
    /// Asks for the permission to notify when a notification is switched
    /// on, and schedules the notifications again.
    private func notificationsChanged(isOn: Bool) {
        if isOn {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        collections.scheduleReminders()
    }
}

/// The name of a pack, which every member can change. The account uploads
/// the new name after the save.
private struct PackNameField: View {
    let pack: Pack

    @Environment(Packs.self) private var packs

    var body: some View {
        NameField("Pack Name", prompt: Text(pack.shownName), name: pack.name) { name in
            try? packs.rename(pack, to: name)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
    }
    .environment(AppSettings())
    .environment(Packs.preview)
    .environment(Account.preview)
    .modelContainer(.preview)
}
