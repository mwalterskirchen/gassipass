//
//  WalkActivity.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import ActivityKit
import Foundation

/// Shows the walk that is being recorded as a Live Activity, on the Lock
/// Screen and in the Dynamic Island, so that the walker sees the key figures
/// without unlocking the phone. It follows the walk recorder and the live
/// feedback, and it ends the Live Activity when the walk ends.
///
/// A Live Activity can start only while the app is in the foreground. When
/// Core Location launches the app in the background during a walk, it
/// continues the Live Activity that already shows the walk.
final class WalkActivity {
    typealias Content = WalkActivityAttributes.ContentState

    /// The shortest time between two updates in which only the distance
    /// changes. It keeps the Live Activity from updating for every GPS point.
    nonisolated static let distanceUpdateInterval: TimeInterval = 10

    private var activity: Activity<WalkActivityAttributes>?
    private var shown: Content?
    private var lastUpdate = Date.distantPast
    private var updates: Task<Void, Never>?

    init(recorder: WalkRecorder, feedback: LiveFeedback) {
        updates = Task { [weak self] in
            let walks = Observations {
                recorder.walk.map { walk in
                    (WalkActivityAttributes(dogNames: walk.dogNames, startedAt: walk.startedAt),
                     Self.content(distanceMetres: recorder.track.distanceMetres, feedback: feedback))
                }
            }
            for await walk in walks {
                guard let self else { return }
                if let (attributes, content) = walk {
                    self.show(content, of: attributes)
                } else {
                    self.endAll()
                }
            }
        }
    }

    /// Whether the Live Activity must show the new content. A new area, a
    /// new completion or a new collected segment shows at once. A longer
    /// distance alone waits for `distanceUpdateInterval` after the last update.
    nonisolated static func needsUpdate(from shown: Content?, to content: Content, lastUpdate: Date, now: Date) -> Bool {
        guard let shown else { return true }
        var withShownDistance = content
        withShownDistance.distanceMetres = shown.distanceMetres
        if withShownDistance != shown { return true }
        return content.distanceMetres != shown.distanceMetres
            && now.timeIntervalSince(lastUpdate) >= distanceUpdateInterval
    }

    private static func content(distanceMetres: Double, feedback: LiveFeedback) -> Content {
        Content(
            distanceMetres: distanceMetres,
            areaName: feedback.currentArea?.name,
            completions: feedback.completions.map { .init(dogName: $0.dogName, share: $0.completion.share) },
            collectedSegmentCount: feedback.collectedOnWalk.count)
    }

    private func show(_ content: Content, of attributes: WalkActivityAttributes) {
        if let activity, activity.attributes.isSameWalk(as: attributes) {
            guard Self.needsUpdate(from: shown, to: content, lastUpdate: lastUpdate, now: .now) else { return }
            shown = content
            lastUpdate = .now
            Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
        } else {
            start(attributes, showing: content)
        }
    }

    /// Continues the Live Activity of the walk, or requests a new one. It
    /// ends the Live Activities of other walks.
    private func start(_ attributes: WalkActivityAttributes, showing content: Content) {
        // In the background a request fails, so try again only after a while.
        guard Date.now.timeIntervalSince(lastUpdate) >= Self.distanceUpdateInterval else { return }
        lastUpdate = .now
        let running = Activity<WalkActivityAttributes>.activities
        let existing = running.first { $0.attributes.isSameWalk(as: attributes) }
        for other in running where other.id != existing?.id {
            Task { await other.end(nil, dismissalPolicy: .immediate) }
        }
        if let existing {
            activity = existing
            Task { await existing.update(ActivityContent(state: content, staleDate: nil)) }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: content, staleDate: nil))
        }
        shown = activity == nil ? nil : content
    }

    /// Ends every Live Activity of a walk, also one that is left from an
    /// earlier launch of the app.
    private func endAll() {
        activity = nil
        shown = nil
        lastUpdate = .distantPast
        for activity in Activity<WalkActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
