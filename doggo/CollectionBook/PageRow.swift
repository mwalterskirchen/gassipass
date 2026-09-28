//
//  PageRow.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// One area with its small map, its completion and the date if the dog has
/// completed it. An area with nothing collected shows a grey map, like an
/// empty page.
struct PageRow: View {
    let page: CollectionBook.Page
    /// A bigger map and a completion bar, for the few pinned areas on the
    /// home screen.
    var isProminent = false

    var body: some View {
        HStack(spacing: 14) {
            AreaMap(area: page.area.id, collectedSegments: page.collectedSegments)
                .frame(width: isProminent ? 84 : 56, height: isProminent ? 84 : 56)
            VStack(alignment: .leading, spacing: isProminent ? 6 : 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(page.area.name)
                        .font(isProminent ? .title3.weight(.semibold) : .headline)
                    Spacer()
                    Text(page.completion.formattedShare)
                        .font(.figures(isProminent ? .title2 : .title3))
                        .monospacedDigit()
                        .foregroundStyle(page.completion.collectedSegmentCount == 0 ? .secondary : .primary)
                }
                if isProminent {
                    CompletionBar(share: page.completion.share)
                }
                if let completedAt = page.completedAt {
                    Label {
                        Text("Completed \(completedAt.formatted(date: .abbreviated, time: .omitted))")
                    } icon: {
                        CompletedSeal()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    Text("\(page.completion.collectedSegmentCount) of \(page.completion.segmentCount) segments")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, isProminent ? 6 : 0)
        .accessibilityElement(children: .combine)
    }
}
