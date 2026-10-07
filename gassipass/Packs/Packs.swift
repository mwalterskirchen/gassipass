//
//  Packs.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import CloudKit
import CoreData
import Observation
import OSLog
import SwiftUI

/// The packs of the person on this phone. It is the only part of the app
/// that knows about the two stores (ADR 0004). The rest of the app reads
/// the packs with `Pack.all()`, and makes and changes them only here.
///
/// A pack of this person lives in the private store. A pack that the person
/// joined lives in the shared store. A new object of a pack goes into the
/// store of that pack, and so into the share of the pack. Core Data puts a
/// new walk or completed record into the store of its dogs by itself, so
/// only a new dog needs `Packs`.
@Observable
final class Packs {
    @ObservationIgnored private let stores: Stores
    @ObservationIgnored private let shares: any PackShares

    /// The number of sync events and removals of members so far. The shares
    /// and the names of their members change only with them, so
    /// `members(of:)` reads the number, and a view that shows names from the
    /// shares renders again after each change.
    private var shareChanges = 0
    /// The packs whose last upload stopped because the iCloud storage of
    /// their pack owner is full (`noteUpload(ofStore:failedWith:)`).
    private var packsWithFullStorage: Set<NSManagedObjectID> = []
    @ObservationIgnored private var syncEventObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var storeChangeObserver: (any NSObjectProtocol)?
    /// The point in the history of the shared store up to which the view
    /// context has the deletions (`mergePurgedObjects()`). It starts at the
    /// launch, because Core Data purges a pack only while the app runs.
    @ObservationIgnored private var sharedStoreHistoryToken: NSPersistentHistoryToken?

    private static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "Packs")

    init(stores: Stores, shares: (any PackShares)? = nil) {
        self.stores = stores
        self.shares = shares ?? ContainerShares(stores: stores)
        // Without a queue, the post does not wait for the main thread. Core
        // Data posts sync events while it blocks the main thread to share a
        // pack, so a post that waits never ends.
        syncEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: stores.container,
            queue: nil
        ) { [weak self] notification in
            let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            // An event is posted at the start and at the end of each sync.
            // Only the end of an upload tells whether the storage is full.
            var upload: (store: String, error: (any Error)?)?
            if let event, event.type == .export, event.endDate != nil, event.succeeded || event.error != nil {
                upload = (event.storeIdentifier, event.succeeded ? nil : event.error)
            }
            Task { @MainActor in
                self?.shareChanges += 1
                if let upload {
                    self?.noteUpload(ofStore: upload.store, failedWith: upload.error)
                }
            }
        }
        sharedStoreHistoryToken = stores.container.persistentStoreCoordinator
            .currentPersistentHistoryToken(fromStores: [stores.sharedStore])
        let sharedStoreID = stores.sharedStore.identifier
        storeChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: stores.container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] notification in
            guard notification.userInfo?[NSStoreUUIDKey] as? String == sharedStoreID else { return }
            Task { @MainActor in
                await self?.mergePurgedObjects()
            }
        }
    }

    private var context: NSManagedObjectContext {
        stores.container.viewContext
    }

    /// All packs of this person, the first made first.
    func all() throws -> [Pack] {
        try context.fetch(Pack.all())
    }

    /// Adds a dog to the pack, or to the default pack when the pack is nil,
    /// and saves it. The default pack is the first own pack of this person,
    /// else the first pack that they joined. A person in no pack first gets
    /// their own pack.
    @discardableResult
    func addDog(named name: String, photoData: Data? = nil, to pack: Pack? = nil) throws -> Dog {
        let pack = try pack ?? defaultPack()
        let dog = Dog(name: name, context: context)
        context.assign(dog, to: store(of: pack))
        dog.photoData = photoData
        dog.pack = pack
        try context.save()
        return dog
    }

    /// Gives the pack a new name, and saves. An empty name gives the pack
    /// its default name.
    func rename(_ pack: Pack, to name: String) throws {
        pack.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    /// Why `Packs` refuses an action.
    enum Refusal: Error {
        /// Only the pack owner may do this.
        case notPackOwner
        /// The pack owner always stays in the pack, because the pack lives
        /// in their iCloud storage. They cannot leave, and nobody removes them.
        case packOwnerStays
    }

    /// Whether the person on this phone is the pack owner. The pack owner
    /// made the pack, so it lives in their private store.
    func isPackOwner(of pack: Pack) -> Bool {
        store(of: pack) == stores.privateStore
    }

    /// The members of the pack, from its share, the pack owner first. A
    /// pack that was never shared has no members to list, because only the
    /// share tells the names.
    func members(of pack: Pack) throws -> [PackMember] {
        // Read, so that a view that shows the members observes the changes.
        _ = shareChanges
        return try shares.members(of: pack).sorted { $0.isPackOwner && !$1.isPackOwner }
    }

    /// The name that the app shows for the pack.
    func shownName(of pack: Pack) -> String {
        guard pack.name.isEmpty else { return pack.name }
        return Pack.defaultName(packOwnerFirstName: packOwner(of: pack)?.firstName)
    }

    /// The name of the person on this phone in the pack, which a new walk
    /// stores (`PackMember.shortName`). It is empty in a pack that was never
    /// shared, because this person is then the pack owner, and an empty
    /// name means the pack owner.
    func memberName(in pack: Pack) -> String {
        let thisPerson = (try? members(of: pack))?.first(where: \.isThisPerson)
        if let name = thisPerson?.shortName {
            return name
        }
        // An empty name would show the walk as a walk of the pack owner.
        return isPackOwner(of: pack) ? "" : PackMember.unknownName
    }

    /// The name of the member who recorded the walk, which the walk stores.
    /// A walk with an empty name shows the pack owner. It is nil while the
    /// app does not know the name of the pack owner, for example in a pack
    /// that was never shared.
    func shownMemberName(of walk: Walk) -> String? {
        guard walk.memberName.isEmpty else { return walk.memberName }
        // All dogs of a walk belong to the same pack.
        guard let pack = walk.dogs.first?.pack else { return nil }
        return packOwnerName(of: pack)
    }

    /// The name of the pack owner, for example in the note that their
    /// iCloud storage is full, or nil while the app does not know it.
    private func packOwnerName(of pack: Pack) -> String? {
        packOwner(of: pack)?.shortName
    }

    /// The pack owner, from the share of the pack, or nil while the app
    /// does not know the share.
    private func packOwner(of pack: Pack) -> PackMember? {
        (try? members(of: pack))?.first(where: \.isPackOwner)
    }

    /// The share of the pack, or nil when the pack was never shared. The
    /// share sheet sends an invitation with the existing share.
    func share(of pack: Pack) -> CKShare? {
        do {
            return try shares.share(of: pack)
        } catch {
            Self.logger.error("The share of the pack cannot load: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The invitation to the pack, which the pack owner sends with the
    /// share sheet.
    func invitation(to pack: Pack) -> PackInvitation {
        // A managed object cannot cross into the closure of the share sheet,
        // so the closure finds the pack again by its ID.
        let id = pack.objectID
        return PackInvitation(share: share(of: pack)) { @MainActor [self] in
            guard let pack = try context.existingObject(with: id) as? Pack else {
                throw CocoaError(.managedObjectReferentialIntegrity)
            }
            return try await shareForInvitation(to: pack)
        }
    }

    /// Shares the pack in a new share for the first invitation. A pack that
    /// has a share keeps it. The title of the share is the name of the pack.
    /// Only the people who get the link can join. Only the pack owner
    /// invites.
    func shareForInvitation(to pack: Pack) async throws -> CKShare {
        guard isPackOwner(of: pack) else { throw Refusal.notPackOwner }
        if let share = try shares.share(of: pack) {
            return share
        }
        // The flag is saved before Core Data moves the pack into the share,
        // so the record of the shared pack always carries it. No phone then
        // takes the shared pack for a first pack (`mergeFirstPacks()`).
        pack.isShared = true
        try context.save()
        let share = try await shares.makeShare(of: pack)
        share.publicPermission = .none
        // The default name of the pack comes from the share. The app can
        // only give the title after the share exists.
        try await save(share, of: pack, title: shownName(of: pack))
        return share
    }

    /// Gives the share of the pack the name of the pack as its title, after
    /// the pack got a new name. Only the pack owner can change the share.
    func updateShareTitle(of pack: Pack) async throws {
        guard isPackOwner(of: pack), let share = try shares.share(of: pack) else { return }
        let title = shownName(of: pack)
        guard share[CKShare.SystemFieldKey.title] as? String != title else { return }
        try await save(share, of: pack, title: title)
    }

    /// Gives the share the title, and saves the share to iCloud.
    private func save(_ share: CKShare, of pack: Pack, title: String) async throws {
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        try await shares.save(share, of: pack)
    }

    /// Accepts the invitation of a share link, and puts its pack into the
    /// shared store. The pack and its dogs arrive with the next import.
    func accept(_ metadata: CKShare.Metadata) async {
        do {
            try await shares.accept(metadata)
        } catch {
            Self.logger.error("The app cannot accept the invitation: \(String(describing: error), privacy: .public)")
        }
    }

    /// Whether the person on this phone may remove the member from the pack.
    /// Only the pack owner removes members, and never themselves.
    func mayRemove(_ member: PackMember, from pack: Pack) -> Bool {
        isPackOwner(of: pack) && !member.isPackOwner
    }

    /// Removes the member from the pack, for example a dog sitter who stops.
    /// Core Data then deletes the pack from the phones of the member, and
    /// the walks that the member recorded stay with the dogs.
    func remove(_ member: PackMember, from pack: Pack) async throws {
        guard isPackOwner(of: pack) else { throw Refusal.notPackOwner }
        guard !member.isPackOwner else { throw Refusal.packOwnerStays }
        try await shares.remove(member, from: pack)
        shareChanges += 1
    }

    /// Whether the person on this phone may leave the pack. Every member
    /// may leave, except the pack owner.
    func mayLeave(_ pack: Pack) -> Bool {
        !isPackOwner(of: pack)
    }

    /// Leaves the pack. The pack and its dogs disappear from this phone, and
    /// this person keeps nothing. The walks that this person recorded stay
    /// with the dogs in the pack.
    func leave(_ pack: Pack) async throws {
        guard mayLeave(pack) else { throw Refusal.packOwnerStays }
        try await shares.leave(pack)
        await mergePurgedObjects()
    }

    /// Deletes the objects that Core Data purged from the shared store also
    /// in the view context, so that the screens stop showing them. Core Data
    /// purges a joined pack when this person leaves it, or when the pack
    /// owner removes them. The purge changes the store file only, and only
    /// its history tells the view context. The deletions stay pending in the
    /// view context until its next save, as with every deletion that Core
    /// Data merges.
    private func mergePurgedObjects() async {
        let coordinator = stores.container.persistentStoreCoordinator
        let since = sharedStoreHistoryToken
        let now = coordinator.currentPersistentHistoryToken(fromStores: [stores.sharedStore])
        // A store cannot cross into the closure, so the closure finds it again
        // by its URL.
        let sharedStoreURL = stores.sharedStore.url
        // A pack can have many walks, so the history loads away from the main
        // thread, and only with its deletions.
        let background = stores.container.newBackgroundContext()
        do {
            let deleted = try await background.perform {
                guard let sharedStore = sharedStoreURL.flatMap(coordinator.persistentStore(for:)) else {
                    throw CocoaError(.persistentStoreOpen)
                }
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: since)
                request.affectedStores = [sharedStore]
                request.resultType = .changesOnly
                let deletions = NSPersistentHistoryChange.fetchRequest
                deletions?.predicate = NSPredicate(
                    format: "changeType == %d", NSPersistentHistoryChangeType.delete.rawValue)
                request.fetchRequest = deletions
                let result = try background.execute(request) as? NSPersistentHistoryResult
                let changes = result?.result as? [NSPersistentHistoryChange] ?? []
                return changes.map(\.changedObjectID)
            }
            // A deletion that arrives during the fetch can come again with the
            // next fetch, and a second merge of a deletion changes nothing.
            sharedStoreHistoryToken = now
            guard !deleted.isEmpty else { return }
            context.mergeChanges(fromContextDidSave: Notification(
                name: .NSManagedObjectContextDidSave, userInfo: [NSDeletedObjectIDsKey: deleted]))
        } catch {
            Self.logger.error("The purged objects cannot merge: \(String(describing: error), privacy: .public)")
        }
    }

    /// The note that the walks of the pack cannot upload, because the iCloud
    /// storage of the pack owner is full, or nil while the pack uploads. All
    /// data of a pack counts against the storage of the pack owner. The walks
    /// stay in the store of the pack, and Core Data uploads them when there
    /// is space again. The note names the pack owner.
    func storageNote(of pack: Pack) -> String? {
        guard packsWithFullStorage.contains(pack.objectID) else { return nil }
        let packName = shownName(of: pack)
        if isPackOwner(of: pack) {
            return String(localized: "Your iCloud storage is full. Walks of “\(packName)” stay on this iPhone and upload when there is space again.")
        }
        guard let packOwnerName = packOwnerName(of: pack) else {
            return String(localized: "The iCloud storage of the pack owner is full. Walks of “\(packName)” stay on this iPhone and upload when there is space again.")
        }
        return String(localized: "The iCloud storage of \(packOwnerName) is full. Walks of “\(packName)” stay on this iPhone and upload when there is space again.")
    }

    /// Notes the end of an upload of the store with the identifier, from a
    /// sync event. An error that says that the iCloud storage is full gives
    /// the packs of the store the note, and an upload that succeeds removes
    /// it. An error with another reason, for example no network, changes
    /// nothing.
    func noteUpload(ofStore storeIdentifier: String, failedWith error: (any Error)?) {
        guard let store = [stores.privateStore, stores.sharedStore].first(where: { $0.identifier == storeIdentifier })
        else { return }
        let request = Pack.all()
        request.affectedStores = [store]
        guard let packsOfStore = try? context.fetch(request) else { return }
        guard let error else {
            // An upload sends all changes of the store that wait, so after a
            // success no pack of the store waits for space.
            packsWithFullStorage.subtract(packsOfStore.map(\.objectID))
            return
        }
        guard let packOwners = Self.ownersWithFullStorage(in: error) else { return }
        // All packs of the private store belong to this person. The shared
        // store has the packs of each pack owner who invited this person, so
        // only the packs of the pack owners in the error get the note. An
        // error that names no pack owner gives it to all packs of the store.
        let full = store == stores.sharedStore && !packOwners.isEmpty
            ? packsOfStore.filter { shares.zoneID(of: $0).map { packOwners.contains($0.ownerName) } ?? false }
            : packsOfStore
        packsWithFullStorage.formUnion(full.map(\.objectID))
    }

    /// The owners of the zones whose upload stopped because their iCloud
    /// storage is full, or nil when the error has another reason. The set is
    /// empty when the error does not name the owners.
    private static func ownersWithFullStorage(in error: any Error) -> Set<String>? {
        if let error = error as? CKError {
            switch error.code {
            case .quotaExceeded:
                return []
            case .partialFailure:
                // An upload of many records tells the error of each record.
                let full = (error.partialErrorsByItemID ?? [:]).filter { ownersWithFullStorage(in: $0.value) != nil }
                guard !full.isEmpty else { return nil }
                return Set(full.keys.compactMap { item in
                    (item as? CKRecord.ID)?.zoneID.ownerName ?? (item as? CKRecordZone.ID)?.ownerName
                })
            default:
                break
            }
        }
        // Core Data can wrap the error of CloudKit in its own error.
        guard let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? any Error else { return nil }
        return ownersWithFullStorage(in: underlying)
    }

    /// Moves the dogs from before the packs into the first pack of this
    /// person that was never shared, by the same rule as the merge of the
    /// first packs, and saves. A person who has such dogs and no such pack
    /// gets one. The first launch of the build with packs moves all dogs.
    func moveDogsWithoutPack() throws {
        // A dog in the shared store always came with its pack.
        let request = Dog.withoutPack()
        request.affectedStores = [stores.privateStore]
        let dogs = try context.fetch(request)
        guard !dogs.isEmpty else { return }
        let pack = try firstUnsharedPack() ?? makeOwnPack()
        for dog in dogs {
            dog.pack = pack
        }
        try context.save()
    }

    /// Merges the first packs of this person into the pack that was made
    /// first, and saves. Two phones of the same person can each make a first
    /// pack before they sync. A first pack is a pack of this person that was
    /// never shared, so a pack that this person shared or joined never
    /// merges.
    ///
    /// Every phone keeps the same pack without talking to the other phones,
    /// because the order of `Pack.all()` breaks ties on the random ID.
    func mergeFirstPacks() throws {
        let ownPacks = try context.fetch(ownPacksRequest())
        // The flag and not the share decides, because a phone can get a pack
        // before its share. A merge of a shared pack would delete it for
        // every member.
        let firstPacks = ownPacks.filter { !$0.isShared }
        guard let kept = firstPacks.first else { return }
        for pack in firstPacks.dropFirst() {
            for dog in pack.dogs {
                dog.pack = kept
            }
            if kept.name.isEmpty {
                kept.name = pack.name
            }
            context.delete(pack)
        }
        try context.save()
    }

    /// Moves the dogs without a pack into a pack, and merges the first packs
    /// of this person. The app calls it at launch, and whenever sync brings a
    /// pack or a dog without a pack (`PackUpdates`). A failed step tries
    /// again at the next call.
    func tidyUp() {
        do {
            try moveDogsWithoutPack()
        } catch {
            Self.logger.error("The dogs cannot move into a pack: \(String(describing: error), privacy: .public)")
        }
        do {
            try mergeFirstPacks()
        } catch {
            Self.logger.error("The first packs cannot merge: \(String(describing: error), privacy: .public)")
        }
    }

    /// The pack for a new dog when the person chooses none: their first own
    /// pack, else the first pack that they joined, else a new own pack.
    private func defaultPack() throws -> Pack {
        let own = ownPacksRequest()
        own.fetchLimit = 1
        let joined = Pack.all()
        joined.affectedStores = [stores.sharedStore]
        joined.fetchLimit = 1
        return try context.fetch(own).first ?? context.fetch(joined).first ?? makeOwnPack()
    }

    /// The first pack of this person that was never shared, which the merge
    /// keeps.
    private func firstUnsharedPack() throws -> Pack? {
        try context.fetch(ownPacksRequest()).first { !$0.isShared }
    }

    /// A request for the packs of this person, the first made first.
    private func ownPacksRequest() -> NSFetchRequest<Pack> {
        let request = Pack.all()
        request.affectedStores = [stores.privateStore]
        return request
    }

    /// The store of the pack. A new pack is not saved yet, and only the
    /// packs of this person are made on this phone.
    private func store(of pack: Pack) -> NSPersistentStore {
        pack.objectID.persistentStore ?? stores.privateStore
    }

    /// Makes a pack of this person in the private store.
    private func makeOwnPack() -> Pack {
        let pack = Pack(context: context)
        context.assign(pack, to: stores.privateStore)
        // CloudKit can store a date with less precision than the phone. A
        // date in whole seconds is the same on every phone, so that every
        // phone puts the packs in the same order.
        pack.createdAt = Date(timeIntervalSinceReferenceDate: Date.now.timeIntervalSinceReferenceDate.rounded(.down))
        pack.randomID = UUID().uuidString
        return pack
    }
}

extension Packs {
    /// The packs of the empty in-memory stores, for previews.
    static let preview = Packs(stores: .preview)
}

/// Tidies the packs whenever sync brings a pack or a dog without a pack from
/// another phone, for example the first pack of the other phone of this
/// person. The app tidies them at launch too.
struct PackUpdates: ViewModifier {
    @Environment(Packs.self) private var packs
    @FetchRequest(fetchRequest: Pack.all()) private var allPacks
    @FetchRequest(fetchRequest: Dog.withoutPack()) private var dogsWithoutPack

    func body(content: Content) -> some View {
        content
            .task(id: packInput) {
                packs.tidyUp()
            }
    }

    /// What the tidy-up depends on. A change starts a new tidy-up.
    private var packInput: Set<NSManagedObjectID> {
        Set(allPacks.map(\.objectID)).union(dogsWithoutPack.map(\.objectID))
    }
}
