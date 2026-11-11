//
//  CompletionFormat.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 11.11.2026.
//

import Foundation
import GassiPassCore

extension Completion {
    /// The completion as a percentage. It rounds down, so that an area or a
    /// street shows 100% only when it is completed.
    var formattedShare: String {
        share.formatted(.completionShare)
    }
}
