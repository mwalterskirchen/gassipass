//
//  BinaryFormat.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 25.10.2026.
//

import Foundation

/// The binary format of the stored matches and the stored history of the
/// collections (`WalkMatchCache`). A property list of them was slow to read
/// and to write, because it has many small values. Each new build of the app
/// starts new caches (`CacheFolder`), so the format needs no migration.
nonisolated struct BinaryWriter {
    private(set) var data = Data()

    mutating func write(_ value: UInt64) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func write(_ value: Int) {
        write(UInt64(bitPattern: Int64(value)))
    }

    mutating func write(_ value: Double) {
        write(value.bitPattern)
    }

    mutating func write(_ value: Bool) {
        data.append(value ? 1 : 0)
    }

    mutating func write(_ value: Date) {
        write(value.timeIntervalSinceReferenceDate)
    }

    mutating func write(_ value: String) {
        let utf8 = Data(value.utf8)
        write(utf8.count)
        data.append(utf8)
    }

    mutating func write(_ value: UUID) {
        withUnsafeBytes(of: value.uuid) { data.append(contentsOf: $0) }
    }
}

/// Reads what a `BinaryWriter` wrote. A value that the data does not hold
/// in full throws.
nonisolated struct BinaryReader {
    enum Error: Swift.Error {
        case truncated
        case invalid
    }

    private let data: Data
    private var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    var isAtEnd: Bool {
        offset == data.count
    }

    mutating func uint64() throws -> UInt64 {
        let bytes = try take(8)
        return UInt64(littleEndian: bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) })
    }

    mutating func int() throws -> Int {
        Int(Int64(bitPattern: try uint64()))
    }

    /// A number of values that follow, each of at least the given size, so
    /// that a damaged file cannot ask for a huge array.
    mutating func count(ofValuesOfAtLeast size: Int) throws -> Int {
        let count = try int()
        guard count >= 0, count <= (data.count - offset) / max(size, 1) else { throw Error.invalid }
        return count
    }

    mutating func double() throws -> Double {
        Double(bitPattern: try uint64())
    }

    mutating func bool() throws -> Bool {
        try take(1).first != 0
    }

    mutating func date() throws -> Date {
        Date(timeIntervalSinceReferenceDate: try double())
    }

    mutating func string() throws -> String {
        let count = try count(ofValuesOfAtLeast: 1)
        guard let string = String(data: try take(count), encoding: .utf8) else { throw Error.invalid }
        return string
    }

    mutating func uuid() throws -> UUID {
        let bytes = try take(16)
        return UUID(uuid: bytes.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) })
    }

    private mutating func take(_ count: Int) throws -> Data {
        guard data.count - offset >= count else { throw Error.truncated }
        let start = data.startIndex + offset
        offset += count
        return data[start..<start + count]
    }
}

nonisolated extension WalkMatch {
    /// The version of the format. A file of another version cannot be read.
    private static let formatVersion = 1

    var data: Data {
        var writer = BinaryWriter()
        writer.write(Self.formatVersion)
        writer.write(entries.count)
        for (id, entry) in entries {
            writer.write(id)
            entry.segment.write(to: &writer)
            writer.write(entry.covered)
        }
        return writer.data
    }

    init(data: Data) throws {
        var reader = BinaryReader(data)
        guard try reader.int() == Self.formatVersion else { throw BinaryReader.Error.invalid }
        self.init()
        for _ in 0..<(try reader.count(ofValuesOfAtLeast: 8)) {
            let id = try reader.string()
            let segment = try MatchedSegment(from: &reader)
            entries[id] = Entry(segment: segment, covered: try reader.coveredIntervals())
        }
        guard reader.isAtEnd else { throw BinaryReader.Error.invalid }
    }
}

nonisolated extension CollectionHistory {
    /// The version of the format. A file of another version cannot be read.
    private static let formatVersion = 1

    var data: Data {
        var writer = BinaryWriter()
        writer.write(Self.formatVersion)
        writer.write(dogs.count)
        for (dog, history) in dogs {
            writer.write(dog)
            writer.write(history.entries.count)
            for (id, entry) in history.entries {
                writer.write(id)
                entry.segment.write(to: &writer)
                writer.write(entry.markedAt != nil)
                entry.markedAt.map { writer.write($0) }
                writer.write(entry.covered)
            }
        }
        writer.write(walks.count)
        for (key, walk) in walks {
            writer.write(key.startedAt)
            writer.write(key.endedAt)
            writer.write(key.distanceMetres)
            writer.write(walk.coversSegments)
            writer.write(walk.dogs.count)
            walk.dogs.forEach { writer.write($0) }
        }
        return writer.data
    }

    init(data: Data) throws {
        var reader = BinaryReader(data)
        guard try reader.int() == Self.formatVersion else { throw BinaryReader.Error.invalid }
        var dogs: [UUID: CoverageHistory] = [:]
        for _ in 0..<(try reader.count(ofValuesOfAtLeast: 16)) {
            let dog = try reader.uuid()
            var entries: [Segment.ID: CoverageHistory.Entry] = [:]
            for _ in 0..<(try reader.count(ofValuesOfAtLeast: 8)) {
                let id = try reader.string()
                let segment = try MatchedSegment(from: &reader)
                let markedAt = try reader.bool() ? try reader.date() : nil
                entries[id] = CoverageHistory.Entry(
                    segment: segment, covered: try reader.coveredIntervals(), markedAt: markedAt)
            }
            dogs[dog] = CoverageHistory(entries: entries)
        }
        var walks: [WalkMatchCache.Key: HeldWalk] = [:]
        for _ in 0..<(try reader.count(ofValuesOfAtLeast: 24)) {
            let key = WalkMatchCache.Key(
                startedAt: try reader.date(), endedAt: try reader.date(), distanceMetres: try reader.double())
            let coversSegments = try reader.bool()
            let walkDogs = try (0..<reader.count(ofValuesOfAtLeast: 16)).map { _ in try reader.uuid() }
            walks[key] = HeldWalk(dogs: Set(walkDogs), coversSegments: coversSegments)
        }
        guard reader.isAtEnd else { throw BinaryReader.Error.invalid }
        self.init(dogs: dogs, walks: walks)
    }
}

nonisolated private extension MatchedSegment {
    func write(to writer: inout BinaryWriter) {
        writer.write(fid)
        writer.write(area)
        writer.write(street != nil)
        if let street {
            writer.write(street.area)
            writer.write(street.name)
        }
        writer.write(lengthMetres)
        writer.write(planeLengthMetres)
    }

    init(from reader: inout BinaryReader) throws {
        let fid = try reader.int()
        let area = try reader.int()
        let street = try reader.bool() ? Street.ID(area: try reader.int(), name: try reader.string()) : nil
        self.init(
            fid: fid, area: area, street: street, lengthMetres: try reader.double(),
            planeLengthMetres: try reader.double())
    }
}

nonisolated private extension BinaryWriter {
    mutating func write(_ intervals: [CoveredInterval]) {
        write(intervals.count)
        for interval in intervals {
            write(interval.date)
            write(interval.interval.lowerBound)
            write(interval.interval.upperBound)
        }
    }
}

nonisolated private extension BinaryReader {
    mutating func coveredIntervals() throws -> [CoveredInterval] {
        try (0..<count(ofValuesOfAtLeast: 24)).map { _ in
            let date = try date(), lower = try double(), upper = try double()
            guard lower <= upper else { throw Error.invalid }
            return CoveredInterval(date: date, interval: lower...upper)
        }
    }
}
