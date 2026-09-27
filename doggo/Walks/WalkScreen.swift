//
//  WalkScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// Shows the walk that is being recorded, until the walker stops it. The map
/// shows the segments near the walker that are new for at least one dog on
/// the walk, and the screen shows the live completion of the current area for
/// each dog.
struct WalkScreen: View {
    @Environment(WalkRecorder.self) private var recorder
    @Environment(LiveFeedback.self) private var feedback
    @State private var isConfirmingStop = false
    @State private var isAskingWhetherEnded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SegmentMapView(shownSegments: feedback.newSegments, zoomLevel: 15)
                    .overlay(alignment: .top) {
                        Label("New segments", systemImage: "circle.fill")
                            .font(.footnote)
                            .labelStyle(NewSegmentsLabelStyle())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.top, 8)
                    }
                    .overlay(alignment: .bottom) {
                        MapAttribution()
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                    }

                VStack(spacing: 16) {
                    if let walk = recorder.walk {
                        Label(walk.dogNames, systemImage: "pawprint")
                            .font(.headline)
                        HStack(alignment: .firstTextBaseline) {
                            TimelineView(.periodic(from: walk.startedAt, by: 1)) { context in
                                Text(WalkFormat.duration(context.date.timeIntervalSince(walk.startedAt)))
                            }
                            Spacer()
                            Text(WalkFormat.distance(recorder.track.distanceMetres))
                        }
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
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
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .confirmationDialog("Stop the walk?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
                        Button("Stop Walk", role: .destructive, action: recorder.stop)
                    }
                }
                .padding()
            }
            .navigationTitle("Walk")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: recorder.askAt) {
            guard let askAt = recorder.askAt else { return }
            try? await Task.sleep(for: .seconds(max(askAt.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            isAskingWhetherEnded = true
        }
        .alert("Has the walk ended?", isPresented: $isAskingWhetherEnded) {
            Button("Stop Walk", role: .destructive, action: recorder.stop)
            Button("Continue Walk", role: .cancel, action: recorder.continueWalk)
        } message: {
            Text("You have not moved for \(WalkRecorder.timeWithoutMovementText).")
        }
    }

    /// The live completion of the current area for each dog on the walk.
    @ViewBuilder
    private var areaCompletion: some View {
        if let area = feedback.currentArea {
            VStack(alignment: .leading, spacing: 8) {
                Text(area.name)
                    .font(.headline)
                ForEach(feedback.completions) { entry in
                    HStack {
                        Text(entry.dogName)
                        Spacer()
                        Text(entry.completion.formattedShare)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    ProgressView(value: entry.completion.share)
                        .tint(Color(SegmentMapView.collectedColor))
                }
            }
        }
    }

    @ViewBuilder
    private var locationStatus: some View {
        switch recorder.locationStatus {
        case .waiting:
            Label("Waiting for GPS", systemImage: "location")
        case .recording(let accuracy):
            Label("GPS accuracy \(Int(accuracy.rounded())) m", systemImage: "location.fill")
        case .unavailable:
            Label("GPS is not available", systemImage: "location.slash")
        case .denied:
            Label("doggo has no access to your location. Allow it in Settings.", systemImage: "location.slash")
        }
    }
}

/// A small dot in the colour of the new segments before the title.
private struct NewSegmentsLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .imageScale(.small)
                .foregroundStyle(Color(SegmentMapView.notCollectedColor))
            configuration.title
        }
    }
}
