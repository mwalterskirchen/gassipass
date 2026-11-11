//
//  WalkActivityUpdates.swift
//  GassiPassWalkActivity
//

import Foundation

/// When the Live Activity of a walk shows new content.
public nonisolated enum WalkActivityUpdates {
    public typealias Content = WalkActivityAttributes.ContentState

    /// The shortest time between two updates in which only the distance
    /// changes. It keeps the Live Activity from updating for every GPS point.
    public static let distanceUpdateInterval: TimeInterval = 10

    /// Whether the Live Activity must show the new content. A new area, a
    /// new completion, a new collected segment or a new location status
    /// shows at once. A longer distance alone waits for
    /// `distanceUpdateInterval` after the last update.
    public static func needsUpdate(from shown: Content?, to content: Content, lastUpdate: Date, now: Date) -> Bool {
        guard let shown else { return true }
        var withShownDistance = content
        withShownDistance.distanceMetres = shown.distanceMetres
        if withShownDistance != shown { return true }
        return content.distanceMetres != shown.distanceMetres
            && now.timeIntervalSince(lastUpdate) >= distanceUpdateInterval
    }
}

nonisolated extension WalkActivityAttributes.ContentState {
    /// This content with the area, the completions and the collected
    /// segments of the shown content.
    public func keepingFeedback(of shown: Self) -> Self {
        var content = self
        content.areaName = shown.areaName
        content.completions = shown.completions
        content.collectedSegmentCount = shown.collectedSegmentCount
        return content
    }
}
