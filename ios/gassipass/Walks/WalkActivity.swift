//
//  WalkActivity.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import ActivityKit
import Foundation

/// Shows the walk that is being recorded as a Live Activity, on the Lock
/// Screen and in the Dynamic Island, so that the walker sees the key figures
/// without unlocking the phone. It follows the current walk and its live
/// feedback, and it ends the Live Activity when the walk ends.
///
/// A Live Activity can start only while the app is in the foreground. When
/// Core Location launches the app in the background during a walk, it takes
/// over the Live Activity that already shows the walk.
final class WalkActivity {
    typealias Content = WalkActivityAttributes.ContentState

    /// The shortest time between two updates in which only the distance
    /// changes. It keeps the Live Activity from updating for every GPS point.
    nonisolated static let distanceUpdateInterval: TimeInterval = 10
    /// The shortest time between two requests for a new Live Activity. A
    /// request fails in the background, so the app tries again only after a while.
    nonisolated static let requestRetryInterval: TimeInterval = 30

    /// What the Live Activity of a walk shows at one moment.
    private struct Snapshot: Sendable {
        let attributes: WalkActivityAttributes
        let content: Content
        /// Whether the live feedback knows the collections and the areas.
        /// Until then its area and completions are empty.
        let isFeedbackReady: Bool
    }

    private var activity: Activity<WalkActivityAttributes>?
    private var shown: Content?
    private var lastUpdate = Date.distantPast
    private var lastRequest = Date.distantPast
    private var updates: Task<Void, Never>?

    init(walk current: CurrentWalk) {
        updates = Task { [weak self] in
            let snapshots = Observations {
                current.walk.map { walk in
                    Snapshot(
                        attributes: WalkActivityAttributes(dogNames: walk.dogNames, startedAt: walk.startedAt),
                        content: Self.content(of: current),
                        isFeedbackReady: current.isReady)
                }
            }
            for await snapshot in snapshots {
                guard let self else { return }
                if let snapshot {
                    self.show(snapshot)
                } else {
                    self.endAll()
                }
            }
        }
    }

    /// Whether the Live Activity must show the new content. A new area, a
    /// new completion, a new collected segment or a new location status
    /// shows at once. A longer distance alone waits for
    /// `distanceUpdateInterval` after the last update.
    nonisolated static func needsUpdate(from shown: Content?, to content: Content, lastUpdate: Date, now: Date) -> Bool {
        guard let shown else { return true }
        var withShownDistance = content
        withShownDistance.distanceMetres = shown.distanceMetres
        if withShownDistance != shown { return true }
        return content.distanceMetres != shown.distanceMetres
            && now.timeIntervalSince(lastUpdate) >= distanceUpdateInterval
    }

    private static func content(of walk: CurrentWalk) -> Content {
        let locationStatus: Content.LocationStatus = switch walk.locationStatus {
        case .waiting: .waiting
        case .recording: .recording
        case .unavailable: .unavailable
        case .denied: .denied
        }
        return Content(
            distanceMetres: walk.distanceMetres,
            areaName: walk.currentArea?.name,
            completions: walk.completions.map { .init(dogName: $0.dogName, share: $0.completion.share) },
            collectedSegmentCount: walk.collectedOnWalk.count,
            locationStatus: locationStatus)
    }

    private func show(_ snapshot: Snapshot) {
        if let activity, activity.attributes.isSameWalk(as: snapshot.attributes) {
            update(activity, to: snapshot)
        } else if let existing = takeOver(snapshot.attributes) {
            activity = existing
            shown = existing.content.state
            lastUpdate = .distantPast
            update(existing, to: snapshot)
        } else {
            request(snapshot)
        }
    }

    private func update(_ activity: Activity<WalkActivityAttributes>, to snapshot: Snapshot) {
        var content = snapshot.content
        // For example just after Core Location launched the app in the
        // background, keep the area and the completions that the Live
        // Activity already shows.
        if !snapshot.isFeedbackReady, let shown {
            content = content.keepingFeedback(of: shown)
        }
        guard Self.needsUpdate(from: shown, to: content, lastUpdate: lastUpdate, now: .now) else { return }
        shown = content
        lastUpdate = .now
        let id = activity.id
        Task { await Self.update(activityWithID: id, to: content) }
    }

    /// The Live Activity that already shows the walk, if any. It ends the
    /// Live Activities of other walks.
    private func takeOver(_ attributes: WalkActivityAttributes) -> Activity<WalkActivityAttributes>? {
        let running = Activity<WalkActivityAttributes>.activities
        let existing = running.first { $0.attributes.isSameWalk(as: attributes) }
        let others = Set(running.map(\.id).filter { $0 != existing?.id })
        Task { await Self.endActivities(withIDs: others) }
        return existing
    }

    private func request(_ snapshot: Snapshot) {
        guard Date.now.timeIntervalSince(lastRequest) >= Self.requestRetryInterval,
              ActivityAuthorizationInfo().areActivitiesEnabled
        else { return }
        lastRequest = .now
        activity = try? Activity.request(
            attributes: snapshot.attributes, content: ActivityContent(state: snapshot.content, staleDate: nil))
        shown = activity == nil ? nil : snapshot.content
        lastUpdate = .now
    }

    /// Ends every Live Activity of a walk, also one that is left from an
    /// earlier launch of the app.
    private func endAll() {
        activity = nil
        shown = nil
        lastUpdate = .distantPast
        lastRequest = .distantPast
        let all = Set(Activity<WalkActivityAttributes>.activities.map(\.id))
        Task { await Self.endActivities(withIDs: all) }
    }

    // `Activity` is not Sendable, so the main actor cannot send one to its
    // async methods. These functions get the IDs and look up the Live
    // Activities themselves.

    @concurrent nonisolated private static func update(activityWithID id: String, to content: Content) async {
        let activity = Activity<WalkActivityAttributes>.activities.first { $0.id == id }
        await activity?.update(ActivityContent(state: content, staleDate: nil))
    }

    @concurrent nonisolated private static func endActivities(withIDs ids: Set<String>) async {
        for activity in Activity<WalkActivityAttributes>.activities where ids.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

nonisolated extension WalkActivityAttributes.ContentState {
    /// This content with the area, the completions and the collected
    /// segments of the shown content.
    func keepingFeedback(of shown: Self) -> Self {
        var content = self
        content.areaName = shown.areaName
        content.completions = shown.completions
        content.collectedSegmentCount = shown.collectedSegmentCount
        return content
    }
}
