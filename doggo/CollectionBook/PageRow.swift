//
//  PageRow.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// One area with its small map, its completion and the date if the dog has
/// completed it.
struct PageRow: View {
    let page: CollectionBook.Page

    var body: some View {
        HStack(spacing: 12) {
            AreaMap(area: page.area.id, collectedSegments: page.collectedSegments)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.area.name)
                    .font(.headline)
                if let completedAt = page.completedAt {
                    Label(completedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color(SegmentMapView.collectedColor))
                } else {
                    Text("\(page.completion.collectedSegmentCount) of \(page.completion.segmentCount) segments")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            Spacer()
            Text(page.completion.formattedShare)
                .monospacedDigit()
        }
    }
}
