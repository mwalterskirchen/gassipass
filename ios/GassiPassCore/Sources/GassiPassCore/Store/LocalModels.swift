//
//  LocalModels.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 07.10.2026.
//

import SwiftData

// The models of the local store, each from the newest version of the
// schema that changed it (`Store/Schema/`). A new version of the schema is a
// new file there, a new entry in the plan below, and the schema of
// `LocalStore`.

public typealias Pack = LocalSchemaV8.Pack
public typealias Dog = LocalSchemaV8.Dog
public typealias Walk = LocalSchemaV8.Walk
public typealias WalkDog = LocalSchemaV8.WalkDog
public typealias CompletedArea = LocalSchemaV8.CompletedArea
public typealias CompletedStreet = LocalSchemaV8.CompletedStreet
public typealias AreaStep = LocalSchemaV3.AreaStep
public typealias CompletedRing = LocalSchemaV4.CompletedRing
public typealias StoredGoalSet = LocalSchemaV6.StoredGoalSet
public typealias WalkedSegment = LocalSchemaV7.WalkedSegment
public typealias CollectionBuild = LocalSchemaV7.CollectionBuild
public typealias PinnedArea = LocalSchemaV1.PinnedArea

/// The steps from each version of the local store to the next.
enum LocalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            LocalSchemaV1.self, LocalSchemaV2.self, LocalSchemaV3.self, LocalSchemaV4.self, LocalSchemaV5.self,
            LocalSchemaV6.self, LocalSchemaV7.self, LocalSchemaV8.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            // The second version only adds the stored collections.
            .lightweight(fromVersion: LocalSchemaV1.self, toVersion: LocalSchemaV2.self),
            // The third version only adds the area steps.
            .lightweight(fromVersion: LocalSchemaV2.self, toVersion: LocalSchemaV3.self),
            // The fourth version only adds the home base and the ring stamps.
            .lightweight(fromVersion: LocalSchemaV3.self, toVersion: LocalSchemaV4.self),
            // The fifth version only adds the marks of the stored collections.
            .lightweight(fromVersion: LocalSchemaV4.self, toVersion: LocalSchemaV5.self),
            // The sixth version only adds the weekly goals.
            .lightweight(fromVersion: LocalSchemaV5.self, toVersion: LocalSchemaV6.self),
            // The seventh version only adds the history of the stored collections.
            .lightweight(fromVersion: LocalSchemaV6.self, toVersion: LocalSchemaV7.self),
            // The eighth version only adds the date of birth and the issue
            // date of a dog. The store fills the issue dates when it opens.
            .lightweight(fromVersion: LocalSchemaV7.self, toVersion: LocalSchemaV8.self),
        ]
    }
}
