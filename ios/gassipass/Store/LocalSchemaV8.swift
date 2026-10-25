//
//  LocalSchemaV8.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 25.10.2026.
//

import Foundation
import SwiftData

/// The eighth version of the local store: the models of `LocalSchemaV7`, and
/// the date of birth and the issue date of a dog, for the identity page of
/// the passport.
///
/// They are new attributes of `Dog`, which the earlier versions share since
/// `LocalSchemaV4`. So this version has its own `Dog`, and its own copy of
/// each model that points to it, directly or through another model, as
/// `LocalSchemaV4` did for the home base. The models without a relationship
/// stay shared.
enum LocalSchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Pack.self, Dog.self, Walk.self, WalkDog.self, CompletedArea.self, CompletedStreet.self,
            LocalSchemaV1.PinnedArea.self, LocalSchemaV7.WalkedSegment.self, LocalSchemaV7.CollectionBuild.self,
            LocalSchemaV3.AreaStep.self, LocalSchemaV4.CompletedRing.self, LocalSchemaV6.StoredGoalSet.self,
        ]
    }

    /// A group of members and the dogs that they walk together.
    @Model
    final class Pack: UploadingRow {
        @Attribute(.unique) var id: UUID = UUID()
        /// The name that a member gave the pack, or empty for the default name.
        var name: String = ""
        var createdAt: Date = Date.now
        /// The home base, the centre of the rings, or nil until a member
        /// sets it. Both coordinates have a value, or neither.
        var homeLatitude: Double?
        var homeLongitude: Double?
        /// The time when a member set the home base.
        var homeSetAt: Date?
        /// Whether a member moved the home base on this phone since its last
        /// upload. Only such a home base uploads, so that a new name from a
        /// phone that has not seen a move keeps the move on the server.
        var isHomeBaseWaitingToUpload: Bool = false
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
        /// The date of birth, as the midnight in Zurich at the start of the
        /// day (`WeekCalendar.date(ofDayText:)`), or nil if the members do
        /// not know it.
        var bornOn: Date?
        /// The issue date of the passport: the time when a member added the
        /// dog to the app. A dog from before the issue dates gets it when
        /// the store opens (`LocalStore.fillMissingIssueDates`).
        var addedAt: Date?
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

        init(id: UUID = UUID(), name: String) {
            self.id = id
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
        /// The device that started the walk (`ThisDevice.id`). A walk from
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

        init(id: UUID = UUID(), startedAt: Date) {
            self.id = id
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

        init(id: UUID = UUID(), walk: Walk, dog: Dog) {
            self.id = id
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
}

typealias Pack = LocalSchemaV8.Pack
typealias Dog = LocalSchemaV8.Dog
typealias Walk = LocalSchemaV8.Walk
typealias WalkDog = LocalSchemaV8.WalkDog
typealias CompletedArea = LocalSchemaV8.CompletedArea
typealias CompletedStreet = LocalSchemaV8.CompletedStreet
