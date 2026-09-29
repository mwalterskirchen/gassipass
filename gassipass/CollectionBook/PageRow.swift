//
//  PageRow.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// One area with its small map and its completion. If the dog has
/// completed the area, a date stamp takes the place of the completion. An
/// area with nothing collected shows a grey map, like an empty page.
struct PageRow: View {
    let page: CollectionBook.Page
    /// A bigger map and a completion bar, for the few pinned areas on the
    /// home screen.
    var isProminent = false

    var body: some View {
        HStack(spacing: 14) {
            AreaMap(area: page.area.id, collectedFeatures: page.collectedFeatures)
                .frame(width: isProminent ? 84 : 56, height: isProminent ? 84 : 56)
            VStack(alignment: .leading, spacing: isProminent ? 6 : 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(page.area.name)
                        .font(isProminent ? .title3.weight(.semibold) : .headline)
                    Spacer()
                    if let completedAt = page.completedAt {
                        DateStamp(date: completedAt)
                    } else {
                        Text(page.completion.formattedShare)
                            .font(.figures(isProminent ? .title2 : .title3))
                            .monospacedDigit()
                            .foregroundStyle(page.completion.collectedSegmentCount == 0 ? .secondary : .primary)
                    }
                }
                if isProminent {
                    CompletionBar(share: page.completion.share)
                }
                Text("\(page.completion.collectedSegmentCount) of \(page.completion.segmentCount) segments")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, isProminent ? 6 : 0)
        .accessibilityElement(children: .combine)
    }
}
