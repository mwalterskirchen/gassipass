//
//  WalkScreen.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// Shows the walk that is being recorded, until the walker stops it.
struct WalkScreen: View {
    @Environment(WalkRecorder.self) private var recorder
    @State private var isConfirmingStop = false
    @State private var isAskingWhetherEnded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                if let walk = recorder.walk {
                    Label(walk.dogNames, systemImage: "pawprint")
                        .font(.title3)

                    TimelineView(.periodic(from: walk.startedAt, by: 1)) { context in
                        Text(WalkFormat.duration(context.date.timeIntervalSince(walk.startedAt)))
                            .font(.system(size: 64, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    Text(WalkFormat.distance(recorder.track.distanceMetres))
                        .font(.title)
                        .monospacedDigit()
                }
                locationStatus
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()

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
            .padding(.top, 48)
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
