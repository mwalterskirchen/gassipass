//
//  Style.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import SwiftUI

extension Font {
    /// Numbers in the condensed width of the system font, like the times
    /// on the yellow hiking signs of Switzerland.
    static func figures(_ style: TextStyle, weight: Weight = .semibold) -> Font {
        .system(style, weight: weight).width(.condensed)
    }

    /// A big number, for example the completion of an area.
    static func bigFigures(size: CGFloat) -> Font {
        .system(size: size, weight: .bold).width(.condensed)
    }
}

extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Percent {
    /// A completion from 0 to 1 as a percentage. It rounds down, so that an
    /// area or a street shows 100% only when it is completed.
    static var completionShare: Self {
        .percent.precision(.fractionLength(0...1)).rounded(rule: .down)
    }
}

extension ButtonStyle where Self == HikingSignButtonStyle {
    /// A big yellow button with black text, like a hiking sign.
    static var hikingSign: HikingSignButtonStyle { HikingSignButtonStyle() }
}

/// The style of `.hikingSign`. It shrinks a little while the button is
/// pressed, and it fades when the button is disabled.
struct HikingSignButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 52)
            .glassEffect(.regular.tint(.collected).interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A thin bar that the collected colour fills.
struct CompletionBar: View {
    let share: Double
    /// The colour of the filled part. On a yellow background, for example
    /// the Live Activity, the bar uses black.
    var fill = Color.collected

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(fill)
                        // A started goal always shows a sliver of colour.
                        .frame(width: share > 0 ? max(geometry.size.width * min(share, 1), 4) : 0)
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// A seal in the collected colour, for completed areas and streets.
struct CompletedSeal: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.black, Color.collected)
    }
}
