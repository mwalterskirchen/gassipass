//
//  LocationSource.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import CoreLocation
import Foundation

/// What the location source reports during the current walk.
nonisolated enum LocationEvent: Equatable, Sendable {
    /// A valid GPS point.
    case point(TrackPoint)
    /// The walker does not allow the app to use the location.
    case denied
    /// The location is not available, for example without a GPS signal.
    case unavailable
}

/// Where the current walk gets its GPS points from.
protocol LocationSource {
    /// Starts the location updates for the current walk, also in the
    /// background. They stop when the iteration of the events ends.
    func start() -> AsyncStream<LocationEvent>
}

/// The location updates of Core Location. The app keeps a service session
/// and a background activity session while the walk runs, so that the
/// updates continue when the phone is locked, and so that Core Location
/// launches the app again when the system terminated it during a walk.
struct CoreLocationSource: LocationSource {
    func start() -> AsyncStream<LocationEvent> {
        // The sessions start at once, also when Core Location has just
        // launched the app in the background.
        let serviceSession = CLServiceSession(authorization: .whenInUse)
        let backgroundSession = CLBackgroundActivitySession()
        let (events, continuation) = AsyncStream<LocationEvent>.makeStream()
        let updates = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                        continuation.yield(.denied)
                    } else if update.locationUnavailable {
                        continuation.yield(.unavailable)
                    }
                    // A negative accuracy marks an invalid location.
                    if let location = update.location, location.horizontalAccuracy >= 0 {
                        continuation.yield(.point(TrackPoint(location: location)))
                    }
                }
            } catch {
                continuation.yield(.unavailable)
            }
        }
        continuation.onTermination = { _ in
            updates.cancel()
            serviceSession.invalidate()
            backgroundSession.invalidate()
        }
        return events
    }
}
