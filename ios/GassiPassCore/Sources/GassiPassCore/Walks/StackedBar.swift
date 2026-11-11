//
//  StackedBar.swift
//  GassiPassCore
//

import Foundation

/// The pieces of a bar that stacks the walks of a day, for the chart of the
/// distance screen and the drawing of the week on the home screen.
public nonisolated enum StackedBar {
    /// The lower and the upper end of each piece, from the bottom up, in
    /// the unit of the distances. A gap separates two pieces, and a very
    /// short distance still shows as a piece of the minimum height. A
    /// distance of 0 gives no piece.
    public static func pieces(of distances: [Double], gap: Double, minimum: Double) -> [ClosedRange<Double>] {
        let parts = distances.filter { $0 > 0 }
        var end = 0.0
        return parts.indices.map { index in
            let lower = end + (index > 0 ? gap / 2 : 0)
            end += parts[index]
            let upper = end - (index < parts.count - 1 ? gap / 2 : 0)
            return lower...max(upper, lower + minimum)
        }
    }
}
