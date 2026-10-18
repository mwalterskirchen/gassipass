//
//  HomeBaseProposal.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 16.10.2026.
//

import Foundation

extension HomeBase {
    /// The home base that the app proposes from the tracks of the ended
    /// walks of the pack, the first walk first, or nil without a walk with
    /// a point. The start of a walk is its first point after the filter of
    /// the track. A track that cannot be read does not count.
    @concurrent nonisolated static func proposal(fromTracks tracks: [Data]) async -> HomeBase? {
        let starts = tracks.compactMap { data in
            (try? Track(data: data))?.filteredPoints.first?.coordinate
        }
        return proposal(fromStarts: starts)
    }
}
