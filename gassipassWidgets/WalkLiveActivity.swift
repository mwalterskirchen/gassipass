//
//  WalkLiveActivity.swift
//  gassipassWidgets
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import ActivityKit
import SwiftUI
import WidgetKit

/// The walk that is being recorded, on the Lock Screen and in the Dynamic
/// Island. The Lock Screen shows it in white on forest green: the time,
/// the distance, the segments collected on the walk, and the live completion
/// of the current area for each dog.
struct WalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.forest)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Figure(time: context.attributes.startedAt, size: 32)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Figure(WalkFormat.distance(context.state.distanceMetres), label: "Distance", size: 32,
                           alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        AreaHeader(state: context.state)
                            .foregroundStyle(Color.collected)
                        AreaCompletions(completions: context.state.completions)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.locationStatus == .recording ? "pawprint.fill" : "location.slash")
                    .foregroundStyle(Color.collected)
            } compactTrailing: {
                Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                    .font(.figures(.subheadline))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56, alignment: .trailing)
            } minimal: {
                Image(systemName: "pawprint.fill")
                    .foregroundStyle(Color.collected)
            }
            .keylineTint(Color.collected)
        }
    }
}

/// The Lock Screen: white on forest green.
private struct LockScreenView: View {
    let attributes: WalkActivityAttributes
    let state: WalkActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(attributes.dogNames, systemImage: "pawprint.fill")
                    .lineLimit(1)
                Spacer()
                PlaceText(state: state)
            }
            .font(.subheadline.weight(.semibold))

            HStack(alignment: .firstTextBaseline) {
                Figure(time: attributes.startedAt, size: 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Figure(WalkFormat.distance(state.distanceMetres), label: "Distance", size: 40, alignment: .center)
                    .frame(maxWidth: .infinity)
                Figure("+\(state.collectedSegmentCount)", label: "Segments", size: 40, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            AreaCompletions(completions: state.completions)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

/// The current area, or a problem with GPS. A problem comes first, because
/// the walk records nothing while it lasts.
private struct PlaceText: View {
    let state: WalkActivityAttributes.ContentState

    var body: some View {
        switch state.locationStatus {
        case .recording:
            Text(state.areaName ?? "")
                .lineLimit(1)
        case .waiting:
            Label("Waiting for GPS", systemImage: "location")
        case .unavailable:
            Label("GPS is not available", systemImage: "location.slash")
        case .denied:
            Label("No access to your location", systemImage: "location.slash")
        }
    }
}

/// The current area and the segments collected on the walk, for the
/// expanded Dynamic Island.
private struct AreaHeader: View {
    let state: WalkActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            PlaceText(state: state)
            Spacer()
            Text("+\(state.collectedSegmentCount) segments")
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
    }
}

/// The live completion of the current area for each dog on the walk.
private struct AreaCompletions: View {
    /// The Lock Screen and the expanded Dynamic Island have room for this many dogs.
    static let maxShownDogs = 3

    let completions: [WalkActivityAttributes.ContentState.DogCompletion]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(completions.prefix(Self.maxShownDogs), id: \.dogName) { entry in
                HStack(spacing: 10) {
                    Text(entry.dogName)
                        .lineLimit(1)
                        .frame(maxWidth: 80, alignment: .leading)
                    CompletionBar(share: entry.share)
                    Text(entry.share.formatted(.completionShare))
                        .font(.figures(.subheadline))
                        .monospacedDigit()
                        .frame(minWidth: 44, alignment: .trailing)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A big number with a small label below it, like on the walk screen.
private struct Figure<Value: View>: View {
    let value: Value
    let label: LocalizedStringKey
    let size: CGFloat
    let alignment: HorizontalAlignment

    init(_ text: String, label: LocalizedStringKey, size: CGFloat, alignment: HorizontalAlignment = .leading)
    where Value == Text {
        self.init(value: Text(text), label: label, size: size, alignment: alignment)
    }

    /// The time since the start of the walk. The system counts it on, so
    /// the app does not update it.
    init(time startedAt: Date, size: CGFloat) where Value == Text {
        self.init(value: Text(timerInterval: startedAt...Date.distantFuture, countsDown: false),
                  label: "Time", size: size, alignment: .leading)
    }

    private init(value: Value, label: LocalizedStringKey, size: CGFloat, alignment: HorizontalAlignment) {
        self.value = value
        self.label = label
        self.size = size
        self.alignment = alignment
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            value
                .font(.bigFigures(size: size))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .opacity(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
private extension WalkActivityAttributes {
    static let preview = WalkActivityAttributes(dogNames: "Bello and Luna", startedAt: .now - 42 * 60)
}

private extension WalkActivityAttributes.ContentState {
    static let waiting = Self(
        distanceMetres: 0, areaName: nil, completions: [], collectedSegmentCount: 0, locationStatus: .waiting)
    static let twoDogs = Self(
        distanceMetres: 3240, areaName: "Dietikon",
        completions: [.init(dogName: "Bello", share: 0.345), .init(dogName: "Luna", share: 0.21)],
        collectedSegmentCount: 12, locationStatus: .recording)
}

#Preview("Lock Screen", as: .content, using: WalkActivityAttributes.preview) {
    WalkLiveActivity()
} contentStates: {
    WalkActivityAttributes.ContentState.waiting
    WalkActivityAttributes.ContentState.twoDogs
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: WalkActivityAttributes.preview) {
    WalkLiveActivity()
} contentStates: {
    WalkActivityAttributes.ContentState.twoDogs
}

#Preview("Compact", as: .dynamicIsland(.compact), using: WalkActivityAttributes.preview) {
    WalkLiveActivity()
} contentStates: {
    WalkActivityAttributes.ContentState.twoDogs
}
#endif
