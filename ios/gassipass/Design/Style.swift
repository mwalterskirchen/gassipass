//
//  Style.swift
//  gassipass
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

extension View {
    /// The font of a big number, at a size that grows and shrinks with
    /// Dynamic Type like the large title.
    func bigFiguresFont(size: CGFloat) -> some View {
        modifier(BigFiguresFont(size: size))
    }
}

private struct BigFiguresFont: ViewModifier {
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    func body(content: Content) -> some View {
        content.font(.bigFigures(size: size))
    }
}

extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Percent {
    /// A completion from 0 to 1 as a percentage. It rounds down, so that an
    /// area or a street shows 100% only when it is completed.
    static var completionShare: Self {
        .percent.precision(.fractionLength(0...1)).rounded(rule: .down)
    }
}

extension ButtonStyle where Self == ForestButtonStyle {
    /// A big forest-green button with white text.
    static var forest: ForestButtonStyle { ForestButtonStyle() }
}

/// The style of `.forest`. It shrinks a little while the button is
/// pressed, and it fades when the button is disabled.
struct ForestButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .glassEffect(.regular.tint(.forest).interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A thin bar that the collected colour fills.
struct CompletionBar: View {
    let share: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.collected)
                        // A started goal always shows a sliver of colour.
                        .frame(width: share > 0 ? max(geometry.size.width * min(share, 1), 4) : 0)
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Animates the change of a value, so that the reader sees what changed,
    /// for example a completion that grows after a walk. It does not animate
    /// when the user reduces motion.
    func animatesChange<Value: Equatable>(of value: Value) -> some View {
        modifier(ChangeAnimation(value: value))
    }
}

private struct ChangeAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .default, value: value)
    }
}
