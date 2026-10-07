//
//  LocalStoreCopy.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 07.10.2026.
//

import CoreData
import Foundation
import SwiftData

extension LocalStore {
    /// Copies the private Core Data store into the SwiftData store, and saves
    /// the copy. Every copied row waits to upload, with the time of the copy
    /// as its change time.
    ///
    /// The shared store stays behind: the phone of a member gets the pack
    /// again through a new invitation (ADR 0006). Packs and completed records
    /// keep their random ID as their stable ID. Dogs and walks had no stable
    /// ID in Core Data, so they get a new one. `Pack.isShared` stays behind,
    /// because only the CloudKit share used it.
    ///
    /// It returns the new ID of each dog by the URI of its Core Data object ID.
    @discardableResult
    static func copyPrivateStore(
        from stores: CoreDataStores, into context: ModelContext, at now: Date
    ) throws -> [URL: UUID] {
        let source = stores.container.viewContext
        func privateObjects<Object: NSManagedObject>(_ type: Object.Type) throws -> [Object] {
            // The name of the class is the name of its entity (`@objc(Dog)`).
            let request = NSFetchRequest<Object>(entityName: NSStringFromClass(Object.self))
            request.affectedStores = [stores.privateStore]
            return try source.fetch(request)
        }
        func insert(_ row: some UploadingRow) {
            row.noteChange(at: now)
            context.insert(row)
        }
        // A record from before iCloud sync has an empty random ID. A random ID
        // that is already taken gets a new one too, because the store would
        // replace the first row with the second.
        var usedIDs: Set<UUID> = []
        func stableID(from randomID: String) -> UUID {
            let id = UUID(uuidString: randomID).flatMap { usedIDs.contains($0) ? nil : $0 } ?? UUID()
            usedIDs.insert(id)
            return id
        }

        var packs: [NSManagedObjectID: LocalSchemaV1.Pack] = [:]
        for pack in try privateObjects(CoreDataStores.Pack.self) {
            let packCopy = LocalSchemaV1.Pack(id: stableID(from: pack.randomID), name: pack.name, createdAt: pack.createdAt)
            insert(packCopy)
            packs[pack.objectID] = packCopy
        }

        var dogs: [NSManagedObjectID: LocalSchemaV1.Dog] = [:]
        func dogCopy(of dog: CoreDataStores.Dog?) -> LocalSchemaV1.Dog? {
            dog.flatMap { dogs[$0.objectID] }
        }
        for dog in try privateObjects(CoreDataStores.Dog.self) {
            let copy = LocalSchemaV1.Dog(name: dog.name)
            copy.photoData = dog.photoData
            copy.retiredAt = dog.retiredAt
            copy.retirementReason = dog.retirementReason
            copy.pack = dog.pack.flatMap { packs[$0.objectID] }
            insert(copy)
            dogs[dog.objectID] = copy
        }

        for walk in try privateObjects(CoreDataStores.Walk.self) {
            let walkCopy = LocalSchemaV1.Walk(startedAt: walk.startedAt)
            walkCopy.endedAt = walk.endedAt
            walkCopy.trackData = walk.trackData
            walkCopy.distanceMetres = walk.distanceMetres
            walkCopy.distanceVersion = walk.distanceVersion
            walkCopy.continuedAt = walk.continuedAt
            walkCopy.deviceID = walk.deviceID
            walkCopy.memberName = walk.memberName
            insert(walkCopy)
            for dog in walk.dogs.compactMap(dogCopy) {
                insert(LocalSchemaV1.WalkDog(walk: walkCopy, dog: dog))
            }
        }

        for area in try privateObjects(CoreDataStores.CompletedArea.self) {
            insert(LocalSchemaV1.CompletedArea(
                id: stableID(from: area.randomID), dog: dogCopy(of: area.dog), area: area.area,
                completedAt: area.completedAt))
        }
        for street in try privateObjects(CoreDataStores.CompletedStreet.self) {
            insert(LocalSchemaV1.CompletedStreet(
                id: stableID(from: street.randomID), dog: dogCopy(of: street.dog), street: street.streetID,
                completedAt: street.completedAt))
        }

        // Two phones could pin the same area on iCloud. On one phone it is one pin.
        for area in Set(try privateObjects(CoreDataStores.PinnedArea.self).map(\.area)) {
            context.insert(LocalSchemaV1.PinnedArea(area: area))
        }

        try context.save()
        return dogs.reduce(into: [:]) { ids, dog in
            ids[dog.key.uriRepresentation()] = dog.value.id
        }
    }
}
