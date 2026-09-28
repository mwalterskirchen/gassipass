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

    /// The day of a walk, for example "Sunday 28 September". It shows the
    /// year only for a walk of an earlier year.
    static func day(_ date: Date) -> String {
        let format = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        return Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
            ? date.formatted(format) : date.formatted(format.year())
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
