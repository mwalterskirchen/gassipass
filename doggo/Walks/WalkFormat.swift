//
//  WalkFormat.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation

/// Formats the numbers that the screens show for a walk.
enum WalkFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded(.down))
            .formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    static func distance(_ metres: Double) -> String {
        Measurement(value: metres, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
