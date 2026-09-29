//
//  WalkScreen.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// Shows the walk that is being recorded, until the walker stops it. The map
/// shows the segments near the walker that are new for at least one dog on
/// the walk, and the screen shows the live completion of the current area for
/// each dog. When dogs complete a street or an area, its stamp lands on the
/// map for a few seconds.
struct WalkScreen: View {
    @Environment(CurrentWalk.self) private var current
    @State private var isConfirmingStop = false
    @State private var isAskingWhetherEnded = false
    /// The stamp on the map, if any: the goal that was completed last.
    @State private var shownStamp: CurrentWalk.CompletedGoal?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SegmentMapView(shownSegments: current.newSegments, zoomLevel: 15)
                    .overlay(alignment: .top) {
                        Label("New segments", systemImage: "circle.fill")
                            .font(.footnote)
                            .labelStyle(MapLegendLabelStyle(isCollected: false))
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
                        if let shownStamp {
                            LandingStamp(goal: shownStamp)
                                .id(shownStamp.id)
                                .onTapGesture { self.shownStamp = nil }
                        }
                    }
                    .animation(.easeOut(duration: 0.4), value: shownStamp)

                VStack(spacing: 20) {
                    if let walk = current.walk {
                        HStack(alignment: .top) {
                            TimelineView(.periodic(from: walk.startedAt, by: 1)) { context in
                                Figure(WalkFormat.duration(context.date.timeIntervalSince(walk.startedAt)),
                                       label: "Time")
                            }
                            Spacer()
                            Figure(WalkFormat.distance(current.distanceMetres), label: "Distance",
                                   alignment: .trailing)
                        }
                    }
                    areaCompletion
                    locationStatus
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button(role: .destructive) {
                        isConfirmingStop = true
                    } label: {
                        Label("Stop Walk", systemImage: "stop.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .controlSize(.large)
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
        .onChange(of: current.completedOnWalk.count) {
            shownStamp = current.completedOnWalk.last
        }
        .task(id: shownStamp?.id) {
            guard shownStamp != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            shownStamp = nil
        }
        .sensoryFeedback(trigger: shownStamp?.id) { _, new in new == nil ? nil : .success }
        .alert("Has the walk ended?", isPresented: $isAskingWhetherEnded) {
            Button("Stop Walk", role: .destructive, action: current.stop)
            Button("Continue Walk", role: .cancel, action: current.continueWalk)
        } message: {
            Text("You have not moved for \(CurrentWalk.timeWithoutMovementText).")
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

/// The stamp of a completed street or area on white, as if it was just
/// pressed onto the map, with what was completed below it. It lands with a
/// short press, unless the user reduces motion.
private struct LandingStamp: View {
    let goal: CurrentWalk.CompletedGoal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLanded = false

    var body: some View {
        VStack(spacing: 20) {
            stamp
                .padding(12)
                .background(.background, in: .circle)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                .scaleEffect(hasLanded || reduceMotion ? 1 : 1.6)
                .opacity(hasLanded ? 1 : 0)
            Text(caption)
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

    @ViewBuilder private var stamp: some View {
        switch goal.id {
        case .area:
            Stamp(area: goal.area, name: goal.name, dogNames: goal.dogNames, date: goal.date, size: 190)
        case .street:
            Stamp(name: goal.name, dogNames: goal.dogNames, date: goal.date, size: 170) {
                Image(systemName: "pawprint.fill")
                    .resizable()
                    .scaledToFit()
            }
        }
    }

    private var caption: LocalizedStringKey {
        switch goal.id {
        case .area: "Area completed"
        case .street: "Street completed"
        }
    }
}

/// A big number with a small label below it.
private struct Figure: View {
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
                .bigFiguresFont(size: 48)
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
