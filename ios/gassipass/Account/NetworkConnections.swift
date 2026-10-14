//
//  NetworkConnections.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Network

/// The network connections of the phone, so that the changes that wait
/// upload when the network comes back.
enum NetworkConnections {
    /// An element each time the phone connects to a network after it had
    /// none.
    static func stream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                var wasConnected = true
                for await path in NWPathMonitor() {
                    let isConnected = path.status == .satisfied
                    if isConnected, !wasConnected {
                        continuation.yield()
                    }
                    wasConnected = isConnected
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
