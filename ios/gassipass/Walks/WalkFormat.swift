//
//  WalkFormat.swift
//  gassipass
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

    /// The day of a walk without its month, for example "Sunday 28".
    static func dayOfMonth(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day())
    }

    /// The day of a walk, for example "Yesterday", or "28 Sep 2026" for a
    /// walk before yesterday.
    static func relativeDay(_ date: Date) -> String {
        relativeDayFormatter.string(from: date)
    }

    /// A date formatter, because a format style has no "Yesterday".
    private static let relativeDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
