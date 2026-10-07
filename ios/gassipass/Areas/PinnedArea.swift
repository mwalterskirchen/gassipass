//
//  PinnedArea.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import SwiftData

/// An area that the user shows on the home screen, to follow its completion.
/// A pin belongs to the phone, not to a dog or a pack, and it does not change
/// what a dog collects. Pins never upload, so unpinning deletes the pin.
extension PinnedArea {
    convenience init(area: Int, context: ModelContext) {
        self.init(area: area)
        context.insert(self)
    }

    /// All pins, in no order.
    static func all() -> FetchDescriptor<PinnedArea> {
        FetchDescriptor()
    }
}
