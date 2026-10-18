//
//  GoalReminders.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 18.10.2026.
//

import Foundation
import UserNotifications

/// A local notification of the weekly goals.
struct GoalNotification: Equatable {
    let id: String
    /// The first time of the notification.
    let date: Date
    let title: String
    let body: String
    /// Whether it comes again every week at the same time, also when the
    /// app does not open in between.
    var repeatsWeekly = false
}

/// Where the phone schedules its local notifications. There is no push
/// server: the phone schedules them itself, like the end-of-walk question.
protocol GoalNotificationCenter {
    /// Schedules the notification, and replaces a planned one with the same ID.
    func add(_ notification: GoalNotification)
    /// Removes the planned notifications with the IDs.
    func remove(ids: [String])
}

/// The notifications of the weekly goals: every Monday at 08:00 that the
/// dogs have new goals, and on Sunday at 17:00 the goal that is left of each
/// dog whose week stamp needs one more goal. Each has a switch in the
/// settings. The collections schedule them again after each update.
final class GoalReminders {
    static let mondayID = "weekly-goals-monday"
    static let sundayID = "weekly-goals-sunday"

    private let center: any GoalNotificationCenter
    private let settings: AppSettings
    /// The notifications that are planned now, so that an update that plans
    /// the same ones changes nothing.
    private var planned: [String: GoalNotification]?

    init(center: any GoalNotificationCenter = SystemGoalNotificationCenter(), settings: AppSettings) {
        self.center = center
        self.settings = settings
    }

    /// Plans the notifications for the dogs that take part in walks, and
    /// removes those that no longer apply.
    ///
    /// - Parameter title: The goal in words.
    func schedule(
        for dogs: [(id: UUID, name: String)], sets: [WeeklyGoalSet], at now: Date, title: (WeeklyGoal) -> String
    ) {
        let notifications = Self.notifications(
            for: dogs, sets: sets, at: now, monday: settings.notifiesAboutNewGoals,
            sunday: settings.notifiesAboutLastGoal, title: title)
        let new = Dictionary(notifications.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard new != planned else { return }
        let removed = [Self.mondayID, Self.sundayID].filter { new[$0] == nil }
        if !removed.isEmpty {
            center.remove(ids: removed)
        }
        for notification in notifications where planned?[notification.id] != notification {
            center.add(notification)
        }
        planned = new
    }

    /// The notifications that apply at the date.
    static func notifications(
        for dogs: [(id: UUID, name: String)], sets: [WeeklyGoalSet], at now: Date, monday: Bool, sunday: Bool,
        title: (WeeklyGoal) -> String
    ) -> [GoalNotification] {
        guard !dogs.isEmpty else { return [] }
        let calendar = WeekCalendar.calendar
        let week = WeekCalendar.week(containing: now)
        var notifications: [GoalNotification] = []
        if monday {
            let thisMonday = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: week.start)!
            let date = now < thisMonday
                ? thisMonday
                : calendar.date(bySettingHour: 8, minute: 0, second: 0, of: week.end)!
            let body = dogs.count == 1
                ? String(localized: "\(dogs[0].name) has three new goals for this week.")
                : String(localized: "Your dogs have new goals for this week.")
            notifications.append(GoalNotification(
                id: mondayID, date: date, title: String(localized: "New weekly goals"), body: body,
                repeatsWeekly: true))
        }
        let sundayEvening = calendar.date(
            bySettingHour: 17, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: 6, to: week.start)!)!
        if sunday, now < sundayEvening {
            let names = Dictionary(dogs.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            let left = sets
                .filter { $0.weekStart.isSameMillisecond(as: week.start) && $0.finishedCount == 2 }
                .compactMap { set in
                    names[set.dog].flatMap { name in
                        set.slots.first { $0.finishedAt == nil }.map { (name: name, goal: $0.goal) }
                    }
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if let first = left.first {
                let body = left.count == 1
                    ? String(localized: "\(first.name) needs one more goal for the week stamp: \(title(first.goal)).")
                    : left.map { String(localized: "\($0.name): \(title($0.goal))") }.joined(separator: "\n")
                notifications.append(GoalNotification(
                    id: sundayID, date: sundayEvening, title: String(localized: "One more goal"), body: body))
            }
        }
        return notifications
    }
}

/// The notification center of the system.
struct SystemGoalNotificationCenter: GoalNotificationCenter {
    func add(_ notification: GoalNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        var components = WeekCalendar.calendar.dateComponents(
            notification.repeatsWeekly ? [.weekday, .hour, .minute] : [.year, .month, .day, .hour, .minute],
            from: notification.date)
        components.calendar = WeekCalendar.calendar
        components.timeZone = WeekCalendar.calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: notification.repeatsWeekly)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger))
    }

    func remove(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
