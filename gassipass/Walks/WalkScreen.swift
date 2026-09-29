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
/// each dog.
struct WalkScreen: View {
    @Environment(CurrentWalk.self) private var current
    @State private var isConfirmingStop = false
    @State private var isAskingWhetherEnded = false

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
