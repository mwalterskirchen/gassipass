//
//  LocalSchema.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 07.10.2026.
//

import Foundation
import SwiftData

/// The SwiftData models of the local store on the phone (ADR 0006). The app
/// uses them through the type aliases below, and adds its behaviour in
/// extensions.
///
/// Every model except `PinnedArea` uploads (`UploadingRow`). The IDs are
/// unique, because the store never syncs with CloudKit.
enum LocalSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Pack.self, Dog.self, Walk.self, WalkDog.self, CompletedArea.self, CompletedStreet.self, PinnedArea.self]
    }

    /// A group of members and the dogs that they walk together.
    @Model
    final class Pack: UploadingRow {
        @Attribute(.unique) var id: UUID = UUID()
        /// The name that a member gave the pack, or empty for the default name.
        var name: String = ""
        var createdAt: Date = Date.now
        @Relationship(inverse: \Dog.pack)
        var dogs: [Dog]? = []

        var isWaitingToUpload: Bool = true
        var changedAt: Date = Date.now
        var deletedAt: Date?

        init(id: UUID = UUID(), name: String, createdAt: Date) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
        }
    }

    /// The owner of a collection. The app never deletes a dog, it retires it.
    @Model
    final class Dog: UploadingRow {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String = ""
        /// A small JPEG of the dog, made by `DogPhoto`.
        @Attribute(.externalStorage)
        var photoData: Data?
        /// The date when the dog became a retired dog, or nil if it still
        /// takes part in walks.
        var retiredAt: Date?
        /// Why the dog became a retired dog, or empty.
        var retirementReason: String = ""
        /// The pack of the dog. Only a dog from before the packs has none,
        /// until the app moves it into a pack.
        var pack: Pack?
        @Relationship(inverse: \WalkDog.dog)
        var walkDogs: [WalkDog]? = []
        @Relationship(inverse: \CompletedArea.dog)
        var completedAreas: [CompletedArea]? = []
        @Relationship(inverse: \CompletedStreet.dog)
        var completedStreets: [CompletedStreet]? = []

        var isWaitingToUpload: Bool = true
        var changedAt: Date = Date.now
        var deletedAt: Date?

        init(name: String) {
            self.name = name
        }
    }

    /// One recording of a GPS track. Its dogs are rows of their own
    /// (`WalkDog`), so that a change to the dogs does not change the walk.
    @Model
    final class Walk: UploadingRow {
        @Attribute(.unique) var id: UUID = UUID()
        var startedAt: Date = Date.now
        var endedAt: Date?
        /// The raw track, encoded by `Track`.
        @Attribute(.externalStorage)
        var trackData: Data?
        /// A cache of the track's distance, so the walk list does not decode
        /// every track.
        var distanceMetres: Double = 0
        /// The version of the rules (`WalkDistance.version`) that calculated
        /// the distance.
        var distanceVersion: Int = 0
        /// The last time the member who records the walk answered that it
        /// has not ended yet.
        var continuedAt: Date?
        /// The device that records the walk (`ThisDevice.id`). A walk from
        /// before iCloud sync has an empty ID.
        var deviceID: String = ""
        /// The first name of the member who recorded the walk. An empty name
        /// means the pack owner.
        var memberName: String = ""
        @Relationship(inverse: \WalkDog.walk)
        var walkDogs: [WalkDog]? = []

        var isWaitingToUpload: Bool = true
        var changedAt: Date = Date.now
        var deletedAt: Date?

        init(startedAt: Date) {
            self.startedAt = startedAt
        }
    }

    /// One dog that takes part in one walk.
    @Model
    final class WalkDog: UploadingRow {
        @Attribute(.unique) var id: UUID = UUID()
        var walk: Walk?
        var dog: Dog?

        var isWaitingToUpload: Bool = true
        var changedAt: Date = Date.now
        var deletedAt: Date?

        init(walk: Walk, dog: Dog) {
            self.walk = walk
            self.dog = dog
        }
    }

    /// The permanent record that a dog has completed an area. With two
    /// phones there can be two records for the same dog and area. The
    /// earliest date counts.
    @Model
    final class CompletedArea: UploadingRow {
        @Attribute(.unique) var id: UUID = UUID()
        var dog: Dog?
        /// The BFS number of the area.
        var area: Int = 0
        var completedAt: Date = Date.now

        var isWaitingToUpload: Bool = true
        var changedAt: Date = Date.now
        var deletedAt: Date?

        init(id: UUID = UUID(), dog: Dog?, area: Int, completedAt: Date) {
            self.id = id
            self.dog = dog
            self.area = area
            self.completedAt = completedAt
        }
    }

    /// The permanent record that a dog has completed a street. It follows
    /// the same rules as `CompletedArea`.
    @Model
    final class CompletedStreet: UploadingRow {
        @Attribute(.unique) var id: UUID = UUID()
        var dog: Dog?
        /// The BFS number of the area of the street.
        var area: Int = 0
        /// The official name of the street.
        var street: String = ""
        var completedAt: Date = Date.now

        var isWaitingToUpload: Bool = true
        var changedAt: Date = Date.now
        var deletedAt: Date?

        init(id: UUID = UUID(), dog: Dog?, street: Street.ID, completedAt: Date) {
            self.id = id
            self.dog = dog
            self.area = street.area
            self.street = street.name
            self.completedAt = completedAt
        }
    }

    /// An area that a member shows on the home screen. Pins belong to the
    /// phone and never upload, so each area has at most one pin.
    @Model
    final class PinnedArea {
        /// The BFS number of the area.
        @Attribute(.unique) var area: Int = 0

        init(area: Int) {
            self.area = area
        }
    }
}

typealias Pack = LocalSchemaV1.Pack
typealias Dog = LocalSchemaV1.Dog
typealias Walk = LocalSchemaV1.Walk
typealias WalkDog = LocalSchemaV1.WalkDog
typealias CompletedArea = LocalSchemaV1.CompletedArea
typealias CompletedStreet = LocalSchemaV1.CompletedStreet
typealias PinnedArea = LocalSchemaV1.PinnedArea

/// A row of the local store that uploads to the server.
nonisolated protocol UploadingRow: PersistentModel {
    /// The stable ID of the row, which is the same on every phone.
    var id: UUID { get }
    /// Whether the row has changed since its last upload.
    var isWaitingToUpload: Bool { get set }
    /// The time of the last change on this phone.
    var changedAt: Date { get set }
    /// The time when the row was deleted, or nil. A deleted row stays, so
    /// that the other phones learn about the deletion.
    var deletedAt: Date? { get set }
}

extension UploadingRow {
    /// Notes a change of the row on this phone, so that the row uploads.
    nonisolated func noteChange(at date: Date = .now) {
        isWaitingToUpload = true
        changedAt = date
    }

    /// Deletes the row. It stays in the store with the deletion time, so
    /// that the deletion uploads, and the app no longer shows it.
    nonisolated func markDeleted(at date: Date = .now) {
        deletedAt = date
        noteChange(at: date)
    }
}
