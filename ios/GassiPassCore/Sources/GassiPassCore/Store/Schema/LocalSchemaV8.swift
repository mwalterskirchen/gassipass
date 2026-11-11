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
public enum LocalSchemaV8: VersionedSchema {
    public static let versionIdentifier = Schema.Version(8, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Pack.self, Dog.self, Walk.self, WalkDog.self, CompletedArea.self, CompletedStreet.self,
            LocalSchemaV1.PinnedArea.self, LocalSchemaV7.WalkedSegment.self, LocalSchemaV7.CollectionBuild.self,
            LocalSchemaV3.AreaStep.self, LocalSchemaV4.CompletedRing.self, LocalSchemaV6.StoredGoalSet.self,
        ]
    }

    /// A group of members and the dogs that they walk together.
    @Model
    public final class Pack: UploadingRow {
        @Attribute(.unique) public var id: UUID = UUID()
        /// The name that a member gave the pack, or empty for the default name.
        public var name: String = ""
        public var createdAt: Date = Date.now
        /// The home base, the centre of the rings, or nil until a member
        /// sets it. Both coordinates have a value, or neither.
        public var homeLatitude: Double?
        public var homeLongitude: Double?
        /// The time when a member set the home base.
        public var homeSetAt: Date?
        /// Whether a member moved the home base on this phone since its last
        /// upload. Only such a home base uploads, so that a new name from a
        /// phone that has not seen a move keeps the move on the server.
        public var isHomeBaseWaitingToUpload: Bool = false
        @Relationship(inverse: \Dog.pack)
        public var dogs: [Dog]? = []

        public var isWaitingToUpload: Bool = true
        public var changedAt: Date = Date.now
        public var deletedAt: Date?

        public init(id: UUID = UUID(), name: String, createdAt: Date) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
        }
    }

    /// The owner of a collection. The app never deletes a dog, it retires it.
    @Model
    public final class Dog: UploadingRow {
        @Attribute(.unique) public var id: UUID = UUID()
        public var name: String = ""
        /// A small JPEG of the dog, made by `DogPhoto`.
        @Attribute(.externalStorage)
        public var photoData: Data?
        /// The date when the dog became a retired dog, or nil if it still
        /// takes part in walks.
        public var retiredAt: Date?
        /// Why the dog became a retired dog, or empty.
        public var retirementReason: String = ""
        /// The date of birth, as the midnight in Zurich at the start of the
        /// day (`WeekCalendar.date(ofDayText:)`), or nil if the members do
        /// not know it.
        public var bornOn: Date?
        /// The issue date of the passport: the time when a member added the
        /// dog to the app. A dog from before the issue dates gets it when
        /// the store opens (`LocalStore.fillMissingIssueDates`).
        public var addedAt: Date?
        /// The pack of the dog. Only a dog from before the packs has none,
        /// until the app moves it into a pack.
        public var pack: Pack?
        @Relationship(inverse: \WalkDog.dog)
        public var walkDogs: [WalkDog]? = []
        @Relationship(inverse: \CompletedArea.dog)
        public var completedAreas: [CompletedArea]? = []
        @Relationship(inverse: \CompletedStreet.dog)
        public var completedStreets: [CompletedStreet]? = []

        public var isWaitingToUpload: Bool = true
        public var changedAt: Date = Date.now
        public var deletedAt: Date?

        public init(id: UUID = UUID(), name: String) {
            self.id = id
            self.name = name
        }
    }

    /// One recording of a GPS track. Its dogs are rows of their own
    /// (`WalkDog`), so that a change to the dogs does not change the walk.
    @Model
    public final class Walk: UploadingRow {
        @Attribute(.unique) public var id: UUID = UUID()
        public var startedAt: Date = Date.now
        public var endedAt: Date?
        /// The raw track, encoded by `Track`.
        @Attribute(.externalStorage)
        public var trackData: Data?
        /// A cache of the track's distance, so the walk list does not decode
        /// every track.
        public var distanceMetres: Double = 0
        /// The version of the rules (`WalkDistance.version`) that calculated
        /// the distance.
        public var distanceVersion: Int = 0
        /// The last time the member who records the walk answered that it
        /// has not ended yet.
        public var continuedAt: Date?
        /// The device that started the walk (`ThisDevice.id`). A walk from
        /// before iCloud sync has an empty ID.
        public var deviceID: String = ""
        /// The first name of the member who recorded the walk. An empty name
        /// means the pack owner.
        public var memberName: String = ""
        @Relationship(inverse: \WalkDog.walk)
        public var walkDogs: [WalkDog]? = []

        public var isWaitingToUpload: Bool = true
        public var changedAt: Date = Date.now
        public var deletedAt: Date?

        public init(id: UUID = UUID(), startedAt: Date) {
            self.id = id
            self.startedAt = startedAt
        }
    }

    /// One dog that takes part in one walk.
    @Model
    public final class WalkDog: UploadingRow {
        @Attribute(.unique) public var id: UUID = UUID()
        public var walk: Walk?
        public var dog: Dog?

        public var isWaitingToUpload: Bool = true
        public var changedAt: Date = Date.now
        public var deletedAt: Date?

        public init(id: UUID = UUID(), walk: Walk, dog: Dog) {
            self.id = id
            self.walk = walk
            self.dog = dog
        }
    }

    /// The permanent record that a dog has completed an area. With two
    /// phones there can be two records for the same dog and area. The
    /// earliest date counts.
    @Model
    public final class CompletedArea: UploadingRow {
        @Attribute(.unique) public var id: UUID = UUID()
        public var dog: Dog?
        /// The BFS number of the area.
        public var area: Int = 0
        public var completedAt: Date = Date.now

        public var isWaitingToUpload: Bool = true
        public var changedAt: Date = Date.now
        public var deletedAt: Date?

        public init(id: UUID = UUID(), dog: Dog?, area: Int, completedAt: Date) {
            self.id = id
            self.dog = dog
            self.area = area
            self.completedAt = completedAt
        }
    }

    /// The permanent record that a dog has completed a street. It follows
    /// the same rules as `CompletedArea`.
    @Model
    public final class CompletedStreet: UploadingRow {
        @Attribute(.unique) public var id: UUID = UUID()
        public var dog: Dog?
        /// The BFS number of the area of the street.
        public var area: Int = 0
        /// The official name of the street.
        public var street: String = ""
        public var completedAt: Date = Date.now

        public var isWaitingToUpload: Bool = true
        public var changedAt: Date = Date.now
        public var deletedAt: Date?

        public init(id: UUID = UUID(), dog: Dog?, street: Street.ID, completedAt: Date) {
            self.id = id
            self.dog = dog
            self.area = street.area
            self.street = street.name
            self.completedAt = completedAt
        }
    }
}
