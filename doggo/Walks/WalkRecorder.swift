//
//  WalkRecorder.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import CoreLocation
import Foundation
import Observation
import SwiftData
import UserNotifications

/// Records the raw GPS points of the current walk, also in the background and
/// without a mobile network. It applies no game rules. It gives each new
/// point to the live feedback.
///
/// The recorder saves the track while it records. When the system terminates
/// the app during a walk, Core Location launches the app again for the next
/// update, and the recorder continues the unfinished walk.
@Observable
final class WalkRecorder {
    enum LocationStatus: Equatable {
        case waiting
        case recording(accuracyMetres: Double)
        case unavailable
        case denied
    }

    /// How often the recorder saves the track during a walk.
    static let saveInterval: TimeInterval = 30
    private static let askNotificationID = "ask-whether-walk-ended"

    /// The time without movement in words, for example "1 hour".
    static var timeWithoutMovementText: String {
        Duration.seconds(StillnessCheck.timeWithoutMovement)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    /// The walk that is being recorded, if any.
    private(set) var walk: Walk?
    private(set) var track = Track()
    private(set) var locationStatus = LocationStatus.waiting
    private var stillness: StillnessCheck?

    /// The time at which the app asks whether the walk has ended.
    var askAt: Date? {
        stillness?.askAt
    }

    private let context: ModelContext
    private let feedback: LiveFeedback
    private var serviceSession: CLServiceSession?
    private var backgroundSession: CLBackgroundActivitySession?
    private var updates: Task<Void, Never>?
    private var lastSave = Date.distantPast

    init(context: ModelContext, feedback: LiveFeedback) {
        self.context = context
        self.feedback = feedback
        let unfinished = FetchDescriptor<Walk>(predicate: #Predicate { $0.endedAt == nil })
        guard let walk = try? context.fetch(unfinished).first else { return }
        do {
            record(walk, track: try walk.readTrack())
        } catch {
            // Recording on would replace the stored points (ADR 0002). End
            // the walk instead and keep its stored track as it is.
            walk.endedAt = .now
            try? context.save()
        }
    }

    func start(dogs: [Dog]) {
        precondition(!dogs.isEmpty, "A walk has at least one dog.")
        guard walk == nil else { return }
        let walk = Walk(startedAt: .now, dogs: dogs)
        context.insert(walk)
        try? context.save()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        record(walk, track: Track())
    }

    func stop() {
        guard let walk else { return }
        updates?.cancel()
        backgroundSession?.invalidate()
        serviceSession?.invalidate()
        feedback.stop()
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.askNotificationID])

        walk.store(track)
        walk.endedAt = .now
        try? context.save()

        self.walk = nil
        track = Track()
        stillness = nil
        locationStatus = .waiting
        updates = nil
        backgroundSession = nil
        serviceSession = nil
    }

    /// The walker answers that the walk has not ended yet.
    func continueWalk() {
        stillness?.walkContinues(at: .now)
        scheduleAskNotification()
    }

    private func record(_ walk: Walk, track: Track) {
        self.walk = walk
        self.track = track
        var stillness = StillnessCheck(startedAt: walk.startedAt)
        track.points.forEach { stillness.add($0) }
        self.stillness = stillness
        scheduleAskNotification()
        feedback.start(dogs: walk.dogs ?? [], track: track)

        serviceSession = CLServiceSession(authorization: .whenInUse)
        backgroundSession = CLBackgroundActivitySession()
        updates = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, !Task.isCancelled else { return }
                    self.handle(update)
                }
            } catch {
                self?.locationStatus = .unavailable
            }
        }
    }

    private func handle(_ update: CLLocationUpdate) {
        if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
            locationStatus = .denied
        } else if update.locationUnavailable {
            locationStatus = .unavailable
        }
        // A negative accuracy marks an invalid location.
        guard let location = update.location, location.horizontalAccuracy >= 0 else { return }

        let point = TrackPoint(location: location)
        track.points.append(point)
        locationStatus = .recording(accuracyMetres: location.horizontalAccuracy)
        feedback.add(point)

        let askAt = stillness?.askAt
        stillness?.add(point)
        if stillness?.askAt != askAt {
            scheduleAskNotification()
        }

        if Date.now.timeIntervalSince(lastSave) >= Self.saveInterval {
            walk?.store(track)
            try? context.save()
            lastSave = .now
        }
    }

    /// Asks with a notification, because the app may not run when the time
    /// comes. In the foreground the walk screen asks instead.
    private func scheduleAskNotification() {
        guard let askAt else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.askNotificationID])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Has the walk ended?")
        content.body = String(localized: "You have not moved for \(Self.timeWithoutMovementText). Open doggo to stop the walk.")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(askAt.timeIntervalSinceNow, 1), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.askNotificationID, content: content, trigger: trigger))
    }
}
