//
//  FileTransfers.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 14.10.2026.
//

import Foundation

/// The uploads and downloads of files in Storage: the GPS tracks and the dog
/// photos. Four files go at the same time. After a failure without a
/// network, no other file starts, so that an upload or a download without a
/// network stops soon.
enum FileTransfers {
    /// The number of files that upload or download at the same time.
    static let atATime = 4

    /// Runs the transfer of each key with its input, four at a time, and
    /// returns the result of each key. A key whose transfer did not start,
    /// because the network failed, gets `NotStarted`.
    static func run<Key: Hashable & Sendable, Input: Sendable, Value: Sendable>(
        _ inputs: [Key: Input], _ transfer: @escaping @MainActor @Sendable (Key, Input) async throws -> Value
    ) async -> [Key: Result<Value, any Error>] {
        var results: [Key: Result<Value, any Error>] = [:]
        await withTaskGroup(of: (Key, Result<Value, any Error>).self) { group in
            var waiting = inputs[...]
            var running = 0
            var isOffline = false
            while true {
                while !isOffline, running < atATime, let next = waiting.popFirst() {
                    let key = next.key
                    let input = next.value
                    group.addTask {
                        do {
                            return (key, .success(try await transfer(key, input)))
                        } catch {
                            return (key, .failure(error))
                        }
                    }
                    running += 1
                }
                guard let finished = await group.next() else { break }
                running -= 1
                results[finished.0] = finished.1
                if case .failure(let error) = finished.1, isWithoutNetwork(error) {
                    isOffline = true
                }
            }
            for next in waiting {
                results[next.key] = .failure(NotStarted())
            }
        }
        return results
    }

    /// Whether the request failed because the phone has no connection to the
    /// server, for example without a network or after a timeout.
    static func isWithoutNetwork(_ error: any Error) -> Bool {
        error is URLError
    }

    /// The transfer did not start, because an earlier one failed without a
    /// network.
    struct NotStarted: Error {}
}
