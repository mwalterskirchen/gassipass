//
//  WalkScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// Shows the walk that is being recorded, until the walker stops it with
/// the hold-to-stop button or answers the end-of-walk question. The map
/// shows the segments near the walker that are new for at least one dog on
/// the walk, the segments that every dog on the walk has collected, and the
/// smallest current ring of the dogs. The screen shows the live completion
/// of the current area for each dog, with the number of segments collected
/// on the walk. When dogs earn a stamp, it lands on the map for a few
/// seconds: the stamp of a completed street, the entry stamp, a step or the
/// full stamp of an area, or a ring stamp.
struct WalkScreen: View {
    @Environment(CurrentWalk.self) private var current
    @State private var isConfirmingStop = false
    @State private var isAskingWhetherEnded = false
    /// The stamp on the map, if any, by its place in the stamps of the walk.
    /// One GPS point can earn several stamps, for example a street and the
    /// entry stamp of its area, so they land one after another.
    @State private var shownIndex: Int?
    /// The place of the next stamp that has not landed yet.
    @State private var nextIndex = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SegmentMapView(
                    shownSegments: current.newSegments, collectedFeatures: current.collectedFeatures,
                    ring: current.currentRing, zoomLevel: 15)
                    .overlay(alignment: .top) {
                        HStack(spacing: 12) {
                            Label("New segments", systemImage: "circle.fill")
                                .labelStyle(MapLegendLabelStyle(isCollected: false))
                            Label("Collected", systemImage: "circle.fill")
                                .labelStyle(MapLegendLabelStyle(isCollected: true))
                        }
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(in: .capsule)
                        .padding(.top, 8)
                    }
                    .overlay(alignment: .bottom) {
                        MapAttribution()
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                    }
                    .overlay {
                        if let shownIndex, current.completedOnWalk.indices.contains(shownIndex) {
                            LandingStamp(goal: current.completedOnWalk[shownIndex])
                                .id(shownIndex)
                                .onTapGesture(perform: showNextStamp)
                        }
                    }
                    .animation(.easeOut(duration: 0.4), value: shownIndex)

                VStack(spacing: 20) {
                    if let walk = current.walk {
                        // The segments collected on the walk are the score,
                        // so they are in the middle.
                        HStack(alignment: .top, spacing: 8) {
                            TimelineView(.periodic(from: walk.startedAt, by: 1)) { context in
                                Figure(WalkFormat.duration(context.date.timeIntervalSince(walk.startedAt)),
                                       label: "Time")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Figure(current.collectedOnWalk.count.formatted(), label: "Collected", alignment: .center)
                                .frame(maxWidth: .infinity)
                                .animation(.default, value: current.collectedOnWalk.count)
                            Figure(WalkFormat.distance(current.distanceMetres), label: "Distance",
                                   alignment: .trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    areaCompletion
                    locationStatus
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HoldToStopButton(stop: current.stop, confirm: { isConfirmingStop = true })
                        .confirmationDialog("Stop the walk?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
                            Button("Stop Walk", role: .destructive, action: current.stop)
                        }
                }
                .padding(20)
            }
            .navigationTitle(current.walk?.dogNames ?? String(localized: "Walk"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: current.askAt) {
            guard let askAt = current.askAt else { return }
            try? await Task.sleep(for: .seconds(max(askAt.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            isAskingWhetherEnded = true
        }
        .onChange(of: current.completedOnWalk.count) { _, count in
            // After a relaunch the stamps of the walk start again.
            if count < nextIndex {
                nextIndex = 0
                shownIndex = nil
            }
            if shownIndex == nil {
                showNextStamp()
            }
        }
        .task(id: shownIndex) {
            guard shownIndex != nil else { return }
            // A stamp that others wait for lands for a shorter time.
            let isWaitedFor = nextIndex < current.completedOnWalk.count
            try? await Task.sleep(for: .seconds(isWaitedFor ? 2.5 : 4))
            guard !Task.isCancelled else { return }
            showNextStamp()
        }
        .sensoryFeedback(trigger: shownIndex) { _, new in new == nil ? nil : .success }
        .alert("Has the walk ended?", isPresented: $isAskingWhetherEnded) {
            Button("Stop Walk", role: .destructive, action: current.stop)
            Button("Continue Walk", role: .cancel, action: current.continueWalk)
        } message: {
            Text("You have not moved for \(CurrentWalk.timeWithoutMovementText).")
        }
    }

    /// Lands the next stamp that has not landed yet, or none.
    private func showNextStamp() {
        if nextIndex < current.completedOnWalk.count {
            shownIndex = nextIndex
            nextIndex += 1
        } else {
            shownIndex = nil
        }
    }

    /// The live completion of the current area for each dog on the walk.
    @ViewBuilder
    private var areaCompletion: some View {
        if let area = current.currentArea {
            VStack(alignment: .leading, spacing: 10) {
                Text(area.name)
                    .font(.headline)
                ForEach(current.completions) { entry in
                    HStack(spacing: 12) {
                        DogBadge(name: entry.dogName, size: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.dogName)
                                Spacer()
                                Text(entry.completion.formattedShare)
                                    .font(.figures(.body))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                            }
                            .font(.subheadline)
                            CompletionBar(share: entry.completion.share)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .animation(.default, value: current.completions.map(\.completion.share))
        }
    }

    @ViewBuilder
    private var locationStatus: some View {
        switch current.locationStatus {
        case .waiting:
            Label("Waiting for GPS", systemImage: "location")
        case .recording(let accuracy):
            Label("GPS accuracy \(Int(accuracy.rounded())) m", systemImage: "location.fill")
        case .unavailable:
            Label("GPS is not available", systemImage: "location.slash")
        case .denied:
            Label("GassiPass has no access to your location. Allow it in Settings.", systemImage: "location.slash")
        }
    }
}

/// The stamp that dogs earned on white, as if it was just pressed onto the
/// map, with what they earned below it. It lands with a short press, unless
/// the user reduces motion.
private struct LandingStamp: View {
    let goal: CurrentWalk.CompletedGoal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLanded = false

    var body: some View {
        VStack(spacing: 20) {
            WalkStamp(goal: goal, size: 190)
                .padding(12)
                .background(.background, in: goal.isEntryStamp ? AnyShape(.rect(cornerRadius: 16)) : AnyShape(.circle))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                .scaleEffect(hasLanded || reduceMotion ? 1 : 1.6)
                .opacity(hasLanded ? 1 : 0)
            Text(goal.caption)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(in: .capsule)
                .opacity(hasLanded ? 1 : 0)
        }
        .transition(.opacity)
        .onAppear {
            withAnimation(.spring(duration: 0.3, bounce: 0.35)) { hasLanded = true }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A big number with a small label below it.
struct Figure: View {
    let value: String
    let label: LocalizedStringKey
    let alignment: HorizontalAlignment

    init(_ value: String, label: LocalizedStringKey, alignment: HorizontalAlignment = .leading) {
        self.value = value
        self.label = label
        self.alignment = alignment
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(value)
                .monospacedDigit()
                .bigFiguresFont(size: 40)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
