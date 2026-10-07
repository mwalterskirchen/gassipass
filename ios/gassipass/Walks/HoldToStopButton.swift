//
//  HoldToStopButton.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import SwiftUI

/// The button that stops the current walk. The walker holds it until red
/// fills it from the left, so that a touch in a pocket cannot stop the walk
/// and the walk needs no question to confirm the stop. Letting go early
/// empties it again.
///
/// VoiceOver cannot hold a button, so its action asks the question instead.
struct HoldToStopButton: View {
    /// Stops the walk, when the button is full.
    let stop: () -> Void
    /// Asks whether to stop the walk, for VoiceOver.
    let confirm: () -> Void

    /// How long the walker holds the button.
    static let holdDuration = 1.2

    @State private var fill = 0.0
    @State private var isPressing = false

    var body: some View {
        ZStack {
            label
                .foregroundStyle(.red)
            label
                .foregroundStyle(.white)
                .background(.red)
                .mask(alignment: .leading) {
                    GeometryReader { geometry in
                        Rectangle().frame(width: geometry.size.width * fill)
                    }
                }
        }
        .clipShape(.capsule)
        .glassEffect(.regular.interactive(), in: .capsule)
        .contentShape(.capsule)
        .onLongPressGesture(minimumDuration: Self.holdDuration) {
            stop()
        } onPressingChanged: { pressing in
            isPressing = pressing
            withAnimation(pressing ? .linear(duration: Self.holdDuration) : .easeOut(duration: 0.25)) {
                fill = pressing ? 1 : 0
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isPressing) { _, pressing in pressing }
        .accessibilityElement()
        .accessibilityLabel(Text("Stop Walk"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { confirm() }
    }

    private var label: some View {
        Label("Hold to Stop Walk", systemImage: "stop.fill")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
    }
}

#Preview {
    HoldToStopButton(stop: {}, confirm: {})
        .padding()
}
