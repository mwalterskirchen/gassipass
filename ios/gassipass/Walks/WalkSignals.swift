//
//  WalkSignals.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import AudioToolbox
import Foundation
import UserNotifications

/// How the current walk reaches the walker when the phone may be in a
/// pocket: a vibration, and a notification that asks whether the walk has
/// ended.
protocol WalkSignals {
    /// Prepares the signals when a walk starts, for example by asking for
    /// the permission to notify.
    func prepare()
    /// Vibrates once, when a segment becomes collected.
    func vibrate()
    /// Asks at the date whether the walk has ended. It replaces the question
    /// that is already planned.
    func ask(at date: Date)
    /// Removes the planned question, when the walk ends.
    func stopAsking()
}

/// The signals of the system: the vibration of the phone, and a local
/// notification, because the app may not run when the time comes.
struct SystemWalkSignals: WalkSignals {
    private static let askNotificationID = "ask-whether-walk-ended"

    func prepare() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func vibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    func ask(at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.askNotificationID])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Has the walk ended?")
        content.body = String(localized: "You have not moved for \(CurrentWalk.timeWithoutMovementText). Open GassiPass to stop the walk.")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(date.timeIntervalSinceNow, 1), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.askNotificationID, content: content, trigger: trigger))
    }

    func stopAsking() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.askNotificationID])
    }
}
