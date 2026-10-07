//
//  PacksTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import CloudKit
import CoreData
import Foundation
import Observation
import Testing
@testable import gassipass

/// The packs of the person on the phone, with an in-memory private store and
/// an in-memory shared store that never sync.
@MainActor
struct PacksTests {
    let stores: Stores
    let packs: Packs
    let context: NSManagedObjectContext

    init() throws {
        stores = try Stores.inMemory()
        packs = Packs(stores: stores, shares: TestShares())
        context = stores.container.viewContext
    }

    @Test func aPersonWhoHasNeverAddedADogHasNoPack() throws {
        #expect(try packs.all().isEmpty)
    }

    @Test func thePersonGetsTheirOwnPackWhenTheyAddTheirFirstDog() throws {
        let bello = try packs.addDog(named: "Bello")

        let all = try packs.all()
        #expect(all.count == 1)
        #expect(bello.pack == all.first)
        #expect(all.first?.dogs == [bello])
    }

    @Test func aSecondDogGoesIntoTheSamePack() throws {
        let bello = try packs.addDog(named: "Bello")
        let luna = try packs.addDog(named: "Luna")

        #expect(try packs.all().count == 1)
        #expect(luna.pack == bello.pack)
    }

    @Test func aDogGoesIntoTheStoreOfItsPack() throws {
        let own = try packs.addDog(named: "Bello").pack
        let joined = Pack(context: context)
        context.assign(joined, to: stores.sharedStore)

        let luna = try packs.addDog(named: "Luna", to: joined)
        let rex = try packs.addDog(named: "Rex", to: own)

        #expect(luna.objectID.persistentStore == stores.sharedStore)
        #expect(rex.objectID.persistentStore == stores.privateStore)
    }

    @Test func theFirstLaunchMovesTheDogsFromBeforeThePacksIntoOnePackWithTheirWalksAndCompletedRecords() throws {
        let bello = Dog(name: "Bello", context: context)
        let luna = Dog(name: "Luna", context: context)
        let walk = Walk(startedAt: .now, dogs: [bello, luna], context: context)
        let record = CompletedArea(dog: bello, area: 243, completedAt: .now, context: context)
        try context.save()

        try packs.moveDogsWithoutPack()

        let all = try packs.all()
        #expect(all.count == 1)
        #expect(all.first?.dogs == [bello, luna])
        #expect(bello.walks == [walk])
        #expect(luna.walks == [walk])
        #expect(bello.completedAreas == [record])
    }

    @Test func theMoveAtLaunchMakesNoPackForAPersonWithNoDogs() throws {
        try packs.moveDogsWithoutPack()

        #expect(try packs.all().isEmpty)
    }

    @Test func aDogWithoutPackFromAnOlderBuildGoesIntoTheExistingOwnPack() throws {
        let bello = try packs.addDog(named: "Bello")
        try packs.moveDogsWithoutPack()
        let luna = Dog(name: "Luna", context: context)
        try context.save()

        try packs.moveDogsWithoutPack()

        #expect(try packs.all().count == 1)
        #expect(luna.pack == bello.pack)
    }

    @Test func aMemberRenamesThePackAndAnEmptyNameGivesTheDefaultNameBack() throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        let defaultName = packs.shownName(of: pack)

        try packs.rename(pack, to: "  Bellos Rudel ")
        let renamed = packs.shownName(of: pack)
        try packs.rename(pack, to: " ")

        #expect(renamed == "Bellos Rudel")
        #expect(packs.shownName(of: pack) == defaultName)
        #expect(!context.hasChanges)
    }

    @Test func twoFirstPacksOfTheSamePersonMergeIntoThePackThatWasMadeFirst() throws {
        let first = makePack(createdAt: .distantPast + 1, in: context)
        let second = makePack(createdAt: .distantPast + 2, in: context)
        let bello = Dog(name: "Bello", context: context)
        bello.pack = second
        let luna = Dog(name: "Luna", context: context)
        luna.pack = first
        let walk = Walk(startedAt: .now, dogs: [bello, luna], context: context)
        let area = CompletedArea(dog: bello, area: 243, completedAt: .now, context: context)
        let street = CompletedStreet(
            dog: luna, street: Street.ID(area: 243, name: "Bremgartnerstrasse"), completedAt: .now, context: context)
        try context.save()

        try packs.mergeFirstPacks()

        #expect(try stores.newContext().fetchAll(Pack.self).map(\.randomID) == [first.randomID])
        #expect(first.dogs == [bello, luna])
        #expect(bello.walks == [walk])
        #expect(luna.walks == [walk])
        #expect(bello.completedAreas == [area])
        #expect(luna.completedStreets == [street])
        #expect(!context.hasChanges)
    }

    @Test func aNewPackHasACreationDateThatSyncKeepsExactly() throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)

        let seconds = pack.createdAt.timeIntervalSinceReferenceDate
        #expect(seconds == seconds.rounded(.down))
    }

    @Test func everyPhoneKeepsTheSamePackWhenBothPacksWereMadeAtTheSameTime() throws {
        let randomIDs = [UUID().uuidString, UUID().uuidString]
        var kept: [[String]] = []
        // Sync brings the pack of the other phone after the own pack, so the
        // two phones insert the packs in the opposite order.
        for order in [randomIDs, randomIDs.reversed()] {
            let phone = try Stores.inMemory()
            let context = phone.container.viewContext
            for randomID in order {
                let pack = makePack(createdAt: .distantPast, randomID: randomID, in: context)
                Dog(name: "Bello", context: context).pack = pack
                try context.save()
            }

            try Packs(stores: phone, shares: TestShares()).mergeFirstPacks()

            kept.append(try context.fetchAll(Pack.self).map(\.randomID))
        }

        #expect(kept.count == 2)
        #expect(kept.first?.count == 1)
        #expect(kept.first == kept.last)
    }

    @Test func aSharedPackNeverMergesAndTheFirstPacksStillMerge() async throws {
        let shared = makePack(createdAt: .distantPast + 1, in: context)
        let first = makePack(createdAt: .distantPast + 2, in: context)
        let second = makePack(createdAt: .distantPast + 3, in: context)
        let bello = Dog(name: "Bello", context: context)
        bello.pack = shared
        let luna = Dog(name: "Luna", context: context)
        luna.pack = second
        try context.save()
        _ = try await packs.shareForInvitation(to: shared)

        try packs.mergeFirstPacks()

        #expect(try packs.all() == [shared, first])
        #expect(bello.pack == shared)
        #expect(luna.pack == first)
    }

    @Test func aPackThatThePackOwnerSharedNeverMergesAlsoWhenItArrivesBeforeItsShare() async throws {
        let first = makePack(createdAt: .distantPast + 1, in: context)
        let shared = makePack(createdAt: .distantPast + 2, in: context)
        let bello = Dog(name: "Bello", context: context)
        bello.pack = shared
        try context.save()
        _ = try await packs.shareForInvitation(to: shared)
        // The other phone of the pack owner has the pack, but not its share yet.
        let otherPhone = Packs(stores: stores, shares: TestShares())

        try otherPhone.mergeFirstPacks()

        #expect(try packs.all() == [first, shared])
        #expect(bello.pack == shared)
    }

    @Test func aJoinedPackNeverMergesWithTheOwnPack() throws {
        let joined = makePack(createdAt: .distantPast + 1, in: context)
        context.assign(joined, to: stores.sharedStore)
        let own = makePack(createdAt: .distantPast + 2, in: context)
        Dog(name: "Bello", context: context).pack = joined
        Dog(name: "Luna", context: context).pack = own
        try context.save()

        try packs.mergeFirstPacks()

        #expect(try packs.all() == [joined, own])
    }

    @Test func theKeptPackTakesTheNameOfTheMergedPackWhenItHasNone() throws {
        let first = makePack(createdAt: .distantPast + 1, in: context)
        let second = makePack(createdAt: .distantPast + 2, in: context)
        second.name = "Bellos Rudel"
        try context.save()

        try packs.mergeFirstPacks()

        #expect(try packs.all() == [first])
        #expect(first.name == "Bellos Rudel")
    }

    @Test func theKeptPackKeepsItsOwnName() throws {
        let first = makePack(createdAt: .distantPast + 1, in: context)
        first.name = "Rudel Dietikon"
        let second = makePack(createdAt: .distantPast + 2, in: context)
        second.name = "Bellos Rudel"
        try context.save()

        try packs.mergeFirstPacks()

        #expect(first.name == "Rudel Dietikon")
    }

    @Test func theInvitationHasTheNameOfThePackAsItsTitleAndNoPublicAccess() async throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        try packs.rename(pack, to: "Bellos Rudel")

        let share = try await packs.shareForInvitation(to: pack)

        #expect(share[CKShare.SystemFieldKey.title] as? String == "Bellos Rudel")
        #expect(share.publicPermission == .none)
    }

    @Test func aRenamedPackGivesItsShareTheNewTitle() async throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        let share = try await packs.shareForInvitation(to: pack)
        try packs.rename(pack, to: "Bellos Rudel")

        try await packs.updateShareTitle(of: pack)

        #expect(share[CKShare.SystemFieldKey.title] as? String == "Bellos Rudel")
        #expect(packs.share(of: pack) == share)
    }

    @Test func onlyThePackOwnerInvitesMembers() async throws {
        let own = try #require(try packs.addDog(named: "Bello").pack)
        let joined = makePack(createdAt: .distantPast, in: context)
        context.assign(joined, to: stores.sharedStore)
        try context.save()

        #expect(packs.isPackOwner(of: own))
        #expect(!packs.isPackOwner(of: joined))
        await #expect(throws: Packs.Refusal.notPackOwner) {
            try await packs.shareForInvitation(to: joined)
        }
    }

    @Test func aPackWithoutNameIsCalledAfterTheFirstNameOfThePackOwner() throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        let defaultName = packs.shownName(of: pack)
        let packs = Packs(stores: stores, shares: TestShares(members: [pack.randomID: [Self.anna, Self.max]]))

        #expect(packs.shownName(of: pack) == Pack.defaultName(packOwnerFirstName: "Max"))
        #expect(packs.shownName(of: pack) != defaultName)
        #expect(try packs.members(of: pack) == [Self.max, Self.anna])
    }

    @Test func aPersonWhoJoinedAPackAndHasNoOwnPackAddsTheirNewDogToTheJoinedPack() throws {
        let joined = makePack(createdAt: .distantPast, in: context)
        context.assign(joined, to: stores.sharedStore)
        try context.save()

        let luna = try packs.addDog(named: "Luna")

        #expect(try packs.all() == [joined])
        #expect(luna.pack == joined)
        #expect(luna.objectID.persistentStore == stores.sharedStore)
    }

    @Test func aDogWithoutPackFromAnOlderBuildNeverGoesIntoASharedPack() async throws {
        let shared = try #require(try packs.addDog(named: "Bello").pack)
        _ = try await packs.shareForInvitation(to: shared)
        let luna = Dog(name: "Luna", context: context)
        try context.save()

        try packs.moveDogsWithoutPack()

        let pack = try #require(luna.pack)
        #expect(pack != shared)
        #expect(!pack.isShared)
    }

    @Test func theNameOfThePersonInASharedPackIsTheirFirstNameFromTheShare() throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        let packs = Packs(stores: stores, shares: TestShares(members: [pack.randomID: [Self.max, Self.anna]]))

        #expect(packs.memberName(in: pack) == "Anna")
    }

    @Test func aMemberWhoseNameICloudDoesNotTellGetsAGeneralNameAndNotTheEmptyNameOfThePackOwner() throws {
        let joined = makePack(createdAt: .distantPast, in: context)
        context.assign(joined, to: stores.sharedStore)
        try context.save()
        var anna = Self.anna
        anna.name = nil
        let packs = Packs(stores: stores, shares: TestShares(members: [joined.randomID: [Self.max, anna]]))

        #expect(packs.memberName(in: joined) == PackMember.unknownName)
    }

    @Test func aMemberWhoseFirstNameICloudDoesNotTellStoresTheirFullName() throws {
        let joined = makePack(createdAt: .distantPast, in: context)
        context.assign(joined, to: stores.sharedStore)
        try context.save()
        var anna = Self.anna
        anna.name = PersonNameComponents(familyName: "Muster")
        let packs = Packs(stores: stores, shares: TestShares(members: [joined.randomID: [Self.max, anna]]))

        #expect(packs.memberName(in: joined) == "Muster")
    }

    @Test func thePersonInAPackThatWasNeverSharedIsThePackOwnerAndHasAnEmptyName() throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)

        #expect(packs.memberName(in: pack) == "")
    }

    @Test func aViewThatShowsTheMembersShowsThemAgainAfterASyncEvent() async throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        let changes = Changes()
        withObservationTracking {
            _ = try? packs.members(of: pack)
        } onChange: {
            changes.count += 1
        }

        NotificationCenter.default.post(
            name: NSPersistentCloudKitContainer.eventChangedNotification, object: stores.container)

        try await eventually { changes.count == 1 }
    }

    /// Core Data blocks the main thread while it shares a pack, and posts
    /// sync events from its own queue meanwhile. A post that waits for the
    /// main thread then never ends, and iOS kills the app.
    @Test func aSyncEventDoesNotWaitForTheMainThread() {
        let container = stores.container
        let posted = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            NotificationCenter.default.post(
                name: NSPersistentCloudKitContainer.eventChangedNotification, object: container)
            posted.signal()
        }

        // The main thread is blocked here, as in the share.
        #expect(posted.wait(timeout: .now() + 2) == .success)
    }

    @Test func aWalkShowsTheNameOfTheMemberWhoRecordedIt() throws {
        let bello = try packs.addDog(named: "Bello")
        let pack = try #require(bello.pack)
        let packs = Packs(stores: stores, shares: TestShares(members: [pack.randomID: [Self.max, Self.anna]]))
        let walk = Walk(startedAt: .now, dogs: [bello], context: context)
        walk.memberName = "Anna"

        #expect(packs.shownMemberName(of: walk) == "Anna")
    }

    @Test func aWalkWithAnEmptyMemberNameShowsThePackOwner() throws {
        let bello = try packs.addDog(named: "Bello")
        let pack = try #require(bello.pack)
        let packs = Packs(stores: stores, shares: TestShares(members: [pack.randomID: [Self.anna, Self.max]]))
        let walk = Walk(startedAt: .now, dogs: [bello], context: context)

        #expect(packs.shownMemberName(of: walk) == "Max")
    }

    @Test func aWalkWithAnEmptyMemberNameInAPackThatWasNeverSharedShowsNoName() throws {
        let bello = try packs.addDog(named: "Bello")
        let walk = Walk(startedAt: .now, dogs: [bello], context: context)

        #expect(packs.shownMemberName(of: walk) == nil)
    }

    @Test func thePackOwnerRemovesAMember() async throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        var max = Self.max
        max.isThisPerson = true
        var anna = Self.anna
        anna.isThisPerson = false
        let packs = Packs(stores: stores, shares: TestShares(members: [pack.randomID: [max, anna]]))

        #expect(packs.mayRemove(anna, from: pack))
        try await packs.remove(anna, from: pack)

        #expect(try packs.members(of: pack) == [max])
    }

    @Test func aMemberWhoIsNotThePackOwnerRemovesNobody() async throws {
        let joined = makePack(createdAt: .distantPast, in: context)
        context.assign(joined, to: stores.sharedStore)
        try context.save()
        let shares = TestShares(members: [joined.randomID: [Self.max, Self.anna, Self.berta]])
        let packs = Packs(stores: stores, shares: shares)

        #expect(!packs.mayRemove(Self.berta, from: joined))
        await #expect(throws: Packs.Refusal.notPackOwner) {
            try await packs.remove(Self.berta, from: joined)
        }
        #expect(try packs.members(of: joined) == [Self.max, Self.anna, Self.berta])
    }

    @Test func nobodyRemovesThePackOwner() async throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        let packs = Packs(stores: stores, shares: TestShares(members: [pack.randomID: [Self.max]]))

        #expect(!packs.mayRemove(Self.max, from: pack))
        await #expect(throws: Packs.Refusal.packOwnerStays) {
            try await packs.remove(Self.max, from: pack)
        }
        #expect(try packs.members(of: pack) == [Self.max])
    }

    @Test func aMemberWhoIsNotThePackOwnerLeavesThePack() async throws {
        let joined = makePack(createdAt: .distantPast, in: context)
        context.assign(joined, to: stores.sharedStore)
        try context.save()
        let shares = TestShares()
        let packs = Packs(stores: stores, shares: shares)

        #expect(packs.mayLeave(joined))
        try await packs.leave(joined)

        #expect(shares.leftPacks == [joined.randomID])
    }

    @Test func thePackOwnerCannotLeaveTheirPack() async throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        let shares = TestShares()
        let packs = Packs(stores: stores, shares: shares)

        #expect(!packs.mayLeave(pack))
        await #expect(throws: Packs.Refusal.packOwnerStays) {
            try await packs.leave(pack)
        }
        #expect(shares.leftPacks.isEmpty)
    }

    /// Core Data deletes a joined pack from the shared store when this person
    /// leaves it or when the pack owner removes them. The deletion does not
    /// reach the view context by itself. The test needs stores in files,
    /// because only they keep the history of their changes.
    @Test func aPackThatCoreDataPurgesFromTheSharedStoreDisappearsFromTheScreen() async throws {
        let folder = URL.temporaryDirectory.appending(path: "PacksTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let stores = try Stores(folder: folder, syncsWithCloudKit: false)
        let packs = Packs(stores: stores, shares: TestShares())
        let context = stores.container.viewContext
        let own = try #require(try packs.addDog(named: "Bello").pack)
        let joined = makePack(createdAt: .distantPast, in: context)
        context.assign(joined, to: stores.sharedStore)
        try packs.addDog(named: "Luna", to: joined)
        // A `@FetchRequest` shows the packs on the screen this way.
        let screen = NSFetchedResultsController(
            fetchRequest: Pack.all(), managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
        let screenUpdates = ScreenUpdates()
        screen.delegate = screenUpdates
        try screen.performFetch()

        try await purge(stores.sharedStore, of: stores)

        try await eventually { screen.fetchedObjects == [own] }
    }

    @Test func aFullICloudStorageShowsTheNoteUntilAnUploadSucceeds() throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        let store: String = stores.privateStore.identifier

        packs.noteUpload(ofStore: store, failedWith: CKError(.quotaExceeded))
        let fullAfterFailure = packs.isStorageFull(of: pack)
        packs.noteUpload(ofStore: store, failedWith: nil)

        #expect(fullAfterFailure)
        #expect(!packs.isStorageFull(of: pack))
    }

    @Test func anUploadThatFailsForAnotherReasonShowsNoNoteAndKeepsAnExistingNote() throws {
        let pack = try #require(try packs.addDog(named: "Bello").pack)
        let store: String = stores.privateStore.identifier

        packs.noteUpload(ofStore: store, failedWith: CKError(.networkUnavailable))
        let fullAfterNetworkFailure = packs.isStorageFull(of: pack)
        packs.noteUpload(ofStore: store, failedWith: CKError(.quotaExceeded))
        packs.noteUpload(ofStore: store, failedWith: CKError(.networkUnavailable))

        #expect(!fullAfterNetworkFailure)
        #expect(packs.isStorageFull(of: pack))
    }

    @Test func aFullStorageOfOnePackOwnerShowsTheNoteOnlyForTheirPacks() throws {
        let own = try #require(try packs.addDog(named: "Bello").pack)
        let ofMax = makePack(createdAt: .distantPast, in: context)
        let ofBerta = makePack(createdAt: .distantPast, in: context)
        context.assign(ofMax, to: stores.sharedStore)
        context.assign(ofBerta, to: stores.sharedStore)
        try context.save()
        var berta = Self.berta
        berta.isPackOwner = true
        let shares = TestShares(members: [ofMax.randomID: [Self.max, Self.anna], ofBerta.randomID: [berta, Self.anna]])
        let packs = Packs(stores: stores, shares: shares)
        // CloudKit tells for each record of the upload why it failed.
        let walkOfMax = CKRecord.ID(recordName: "walk", zoneID: try #require(shares.zoneID(of: ofMax)))
        let walkOfBerta = CKRecord.ID(recordName: "walk", zoneID: try #require(shares.zoneID(of: ofBerta)))
        let error = CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: [walkOfMax: CKError(.quotaExceeded), walkOfBerta: CKError(.batchRequestFailed)],
        ])

        packs.noteUpload(ofStore: stores.sharedStore.identifier, failedWith: error)

        #expect(packs.isStorageFull(of: ofMax))
        #expect(!packs.isStorageFull(of: ofBerta))
        #expect(!packs.isStorageFull(of: own))
    }

    @Test func theNoteNamesThePackOwner() throws {
        let joined = makePack(createdAt: .distantPast, in: context)
        context.assign(joined, to: stores.sharedStore)
        try context.save()
        let packs = Packs(stores: stores, shares: TestShares(members: [joined.randomID: [Self.anna, Self.max]]))

        #expect(packs.packOwnerName(of: joined) == "Max")
    }

    /// Deletes all packs and dogs of the store in one batch, as Core Data
    /// purges the zone of a pack.
    private func purge(_ store: NSPersistentStore, of stores: Stores) async throws {
        let context = stores.container.newBackgroundContext()
        let coordinator = stores.container.persistentStoreCoordinator
        let url = store.url
        try await context.perform {
            guard let store = url.flatMap(coordinator.persistentStore(for:)) else {
                throw CocoaError(.persistentStoreOpen)
            }
            for entityName in ["Dog", "Pack"] {
                let request = NSBatchDeleteRequest(fetchRequest: NSFetchRequest(entityName: entityName))
                request.affectedStores = [store]
                try context.execute(request)
            }
        }
    }

    /// The pack owner, as the share of a pack lists them for Anna.
    static let max = PackMember(
        id: "max", name: PersonNameComponents(givenName: "Max", familyName: "Muster"),
        isPackOwner: true, isThisPerson: false, hasAccepted: true)
    /// A member who is the person on this phone.
    static let anna = PackMember(
        id: "anna", name: PersonNameComponents(givenName: "Anna", familyName: "Muster"),
        isPackOwner: false, isThisPerson: true, hasAccepted: true)
    /// Another member, who is not the person on this phone.
    static let berta = PackMember(
        id: "berta", name: PersonNameComponents(givenName: "Berta", familyName: "Beispiel"),
        isPackOwner: false, isThisPerson: false, hasAccepted: true)

    /// A pack of this person, as the first launch of the build with packs
    /// makes it on one of their phones.
    private func makePack(
        createdAt: Date, randomID: String = UUID().uuidString, in context: NSManagedObjectContext
    ) -> Pack {
        let pack = Pack(context: context)
        pack.createdAt = createdAt
        pack.randomID = randomID
        return pack
    }
}

/// The delegate that makes a fetched results controller follow the changes
/// of its context, as a `@FetchRequest` does.
private final class ScreenUpdates: NSObject, NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {}
}

/// The number of changes that an observation saw.
private final class Changes: @unchecked Sendable {
    var count = 0
}
