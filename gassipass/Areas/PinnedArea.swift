//
//  PinnedArea.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import SwiftData

/// An area that the user shows on the home screen, to follow its completion.
/// A pin belongs to the user, not to a dog, and it does not change what a
/// dog collects.
///
/// The model follows the CloudKit rules of SwiftData, like `Dog`. With two
/// devices there can be two pins for the same area. The area shows once, and
/// unpinning removes all of its pins.
@Model
final class PinnedArea {
    /// The BFS number of the area.
    var area: Int = 0

    init(area: Int) {
        self.area = area
    }
}
