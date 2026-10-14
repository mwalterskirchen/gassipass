//
//  Account.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 09.10.2026.
//

import Foundation
import Observation
import OSLog
import SwiftData

/// The account of the person on this phone (ADR 0006). After the sign-in,
/// the member name and the pack of the phone upload to the server, with its
/// dogs, walks and completed records (`PackUpload`). Each change uploads
/// soon after it is saved. The changes of the other phones of the pack
/// download at the sign-in, when the app opens, when it comes to the
/// foreground and on pull to refresh (`PackDownload`). Without an account,
/// the app makes no request to the server.
///
/// The phone keeps the member name, so that a change made without a network
/// uploads later.
@Observable
final class Account {
    /// Whether the person has signed in on this phone.
    private(set) var isSignedIn: Bool
    /// The name of the member, or empty before the person gives one.
    private(set) var memberName: String {
        didSet {
            defaults.set(memberName, forKey: Self.memberNameKey)
        }
    }

    /// The number of changes on this phone that wait to upload.
    private(set) var waitingChanges = 0

    /// The members of the pack of the account, the pack owner first. They
    /// load with each download, and stay empty without an account.
    private(set) var packMembers: [PackMember] = []

    /// The pack of the account, while this phone has another pack whose dogs
    /// wait for a confirmation to move into it (ADR 0005). Until then, the
    /// pack of this phone neither uploads nor downloads.
    private(set) var packOfAccount: ServerPack?

    /// Whether the person is the pack owner of the pack of the account. Only
    /// a pack owner with an account invites (glossary, «Invitation»).
    var isPackOwner: Bool {
        isSignedIn && packMembers.contains { $0.isThisPerson && $0.isPackOwner }
    }

    /// Whether the person can leave the pack of the account: a member who is
    /// not the pack owner.
    var canLeavePack: Bool {
        isSignedIn && packMembers.contains { $0.isThisPerson && !$0.isPackOwner }
    }

    /// The move of the dogs of this phone that the person has agreed to: from
    /// the pack of this phone into another pack. The user defaults keep it,
    /// so that the move happens also after a failure or a restart of the app.
    /// It stays until the move, because an upload during the join still sees
    /// the old pack.
    @ObservationIgnored private var agreedMove: PackMove? {
        get {
            guard let move = defaults.dictionary(forKey: Self.agreedMoveKey) as? [String: String],
                  let pack = move["pack"].flatMap(UUID.init(uuidString:)),
                  let into = move["into"].flatMap(UUID.init(uuidString:)) else { return nil }
            return PackMove(pack: pack, into: into)
        }
        set {
            let move = newValue.map { ["pack": $0.pack.uuidString, "into": $0.into.uuidString] }
            defaults.set(move, forKey: Self.agreedMoveKey)
        }
    }

    /// A move of the dogs of a pack into another pack.
    private struct PackMove: Equatable {
        var pack: UUID
        var into: UUID
    }

    /// Whether the member name has changed since its last upload.
    @ObservationIgnored private var isMemberNameWaitingToUpload: Bool {
        get { defaults.bool(forKey: Self.memberNameWaitingKey) }
        set { defaults.set(newValue, forKey: Self.memberNameWaitingKey) }
    }

    /// The running upload, which the callers wait for.
    @ObservationIgnored private var running: Task<Void, Never>?
    /// Whether a call came during the running upload.
    @ObservationIgnored private var uploadsAgain = false
    /// Whether a download waits for the running upload.
    @ObservationIgnored private var isDownloadDue = false
    /// The time when the last upload started. A save starts an upload only
    /// when a row has changed since, so a row that keeps failing, or a pack
    /// that waits for its move (ADR 0005), does not upload at each save.
    @ObservationIgnored private var lastUploadStartedAt = Date.distantPast

    @ObservationIgnored private let server: (any Server)?
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let uploadedFiles: UploadedFiles
    @ObservationIgnored private let downloadCursors: DownloadCursors

    private static let memberNameKey = "memberName"
    private static let memberNameWaitingKey = "memberNameIsWaitingToUpload"
    private static let agreedMoveKey = "agreedPackMove"
    private static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "Account")

    /// - Parameter server: The server, or nil when the build has no
    ///   Supabase keys. Then nobody can sign in.
    init(server: (any Server)?, context: ModelContext, defaults: UserDefaults = .standard) {
        self.server = server
        self.context = context
        self.defaults = defaults
        uploadedFiles = UploadedFiles(defaults: defaults)
        downloadCursors = DownloadCursors(defaults: defaults)
        isSignedIn = server?.isSignedIn ?? false
        memberName = defaults.string(forKey: Self.memberNameKey) ?? ""
        countWaitingChanges()
    }

    /// Whether this build can sign in.
    var canSignIn: Bool {
        server != nil
    }

    /// Signs in with Sign in with Apple, uploads and downloads. Apple gives
    /// the name of the person only at their first sign-in, and it becomes the
    /// member name.
    func signIn(with credential: AppleCredential) async throws {
        guard let server else { throw AccountError.noServer }
        // The phone keeps the name before the request, because a failed
        // sign-in does not get it again.
        if let givenName = credential.givenName {
            changeMemberName(to: givenName)
        }
        try await server.signIn(appleIDToken: credential.idToken, nonce: credential.nonce)
        isSignedIn = true
        await refresh()
    }

    /// Gives the member a new name, and uploads it.
    func renameMember(to name: String) async {
        changeMemberName(to: name)
        await upload()
    }

    /// Makes an invitation to the pack of the account, and returns its link.
    /// Only the pack owner can invite.
    func makeInvitationLink() async throws -> URL {
        let server = try signedInServer()
        return InvitationLink.url(token: try await server.createInvitation())
    }

    /// Whether the person can join with the invitation, and its pack.
    func checkInvitation(token: String) async throws -> Invitation {
        try await signedInServer().checkInvitation(token: token)
    }

    /// Joins the pack of the invitation, and then downloads it. The dogs of
    /// this phone come along, with their walks and completed records, and
    /// the pack of this phone disappears (ADR 0005). It returns `.joined`,
    /// or the state of the invitation that keeps the person out.
    func join(token: String) async throws -> InvitationState {
        let server = try signedInServer()
        let invitation = try await server.checkInvitation(token: token)
        guard invitation.state == .open, let packID = invitation.packID else { return invitation.state }
        try agreeToMove(into: packID)
        let state = try await server.joinPack(token: token)
        if state == .joined {
            await refresh()
        } else {
            agreedMove = nil
        }
        return state
    }

    /// Moves the dogs of this phone, with their walks and completed records,
    /// into the pack of the account, after the person has agreed. The pack
    /// of this phone then disappears (ADR 0005).
    func moveDogsIntoPackOfAccount() async {
        guard let packOfAccount else { return }
        do {
            try agreeToMove(into: packOfAccount.id)
        } catch {
            Self.logger.error("The pack cannot be read: \(String(describing: error), privacy: .public)")
            return
        }
        await refresh()
    }

    /// Takes the account out of its pack, after the changes of this phone
    /// have uploaded, so that the walks of the person stay with the dogs.
    /// The refresh after it deletes the data of the pack from this phone.
    /// The pack owner cannot leave.
    func leavePack() async throws {
        let server = try signedInServer()
        await upload()
        try await server.leavePack()
        await refresh()
    }

    /// Takes the member out of the pack of the account. Only the pack owner
    /// removes a member, and not themselves. The phones of the member delete
    /// the data of the pack at their next download.
    func removeMember(_ member: PackMember) async throws {
        let server = try signedInServer()
        try await server.removeMember(id: member.id)
        packMembers = try await server.packMembers()
    }

    /// Notes that the person agrees to move the dogs of this phone into the
    /// pack.
    private func agreeToMove(into packID: UUID) throws {
        agreedMove = try context.fetch(Pack.all()).first.map { PackMove(pack: $0.id, into: packID) }
    }

    private func signedInServer() throws -> any Server {
        guard let server else { throw AccountError.noServer }
        guard isSignedIn else { throw AccountError.notSignedIn }
        return server
    }

    /// Uploads what has changed: the member name, the pack and its rows. A
    /// failed upload is logged, and the next upload tries again.
    ///
    /// Only one upload runs at a time. A call during an upload, or a row that
    /// changed during it, makes the upload start again when it ends, so that
    /// the newest change reaches the server last.
    func upload() async {
        await run(downloads: false)
    }

    /// Uploads what has changed, and then downloads the changes of the pack
    /// from the other phones. A failed download is logged, and the next
    /// download tries again. A call during an upload downloads after it.
    func refresh() async {
        await run(downloads: true)
    }

    /// Starts the upload, or asks the running upload to start again. Either
    /// way, it returns when the upload has ended. The upload runs in a task
    /// of its own, so that it continues when the caller is cancelled, for
    /// example when the app leaves the foreground.
    private func run(downloads: Bool) async {
        guard let server, isSignedIn else { return }
        if downloads {
            isDownloadDue = true
        }
        if let running {
            uploadsAgain = true
            await running.value
            return
        }
        let task = Task {
            await runUntilDone(with: server)
            running = nil
        }
        running = task
        await task.value
    }

    private func runUntilDone(with server: any Server) async {
        repeat {
            uploadsAgain = false
            let downloads = isDownloadDue
            isDownloadDue = false
            lastUploadStartedAt = .now
            await runOnce(with: server, downloads: downloads)
        } while uploadsAgain || hasChanges(since: lastUploadStartedAt)
        countWaitingChanges()
    }

    /// Uploads each change soon after it is saved, and the waiting changes
    /// when the phone connects to a network again. It runs until its task is
    /// cancelled.
    ///
    /// - Parameter connections: An element for each new network connection.
    func uploadChanges(whenConnected connections: some AsyncSequence<Void, Never> & Sendable) async {
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                    await self.changesSaved()
                }
            }
            group.addTask {
                for await _ in connections {
                    await self.upload()
                }
            }
        }
    }

    /// A save during an upload is often the upload's own save. The upload
    /// checks for changes when it ends, so the save starts nothing.
    private func changesSaved() async {
        countWaitingChanges()
        guard running == nil, hasChanges(since: lastUploadStartedAt) else { return }
        await upload()
    }

    /// Whether a row that waits to upload changed between the date and now.
    private func hasChanges(since date: Date) -> Bool {
        do {
            return try PackUpload.hasChanges(between: date, and: .now, in: context)
        } catch {
            Self.logger.error("The changes cannot be read: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Counts the changes that wait to upload: the member name and the rows
    /// of the pack.
    private func countWaitingChanges() {
        do {
            waitingChanges = try PackUpload.waitingRows(in: context) + (isMemberNameWaitingToUpload ? 1 : 0)
        } catch {
            Self.logger.error("The waiting changes cannot be counted: \(String(describing: error), privacy: .public)")
        }
    }

    /// Uploads once, and downloads after it if asked. A failure is logged.
    private func runOnce(with server: any Server, downloads: Bool) async {
        let member: ServerMember
        do {
            member = try await server.member()
        } catch {
            Self.logger.error("The member cannot be read: \(String(describing: error), privacy: .public)")
            return
        }
        do {
            try await upload(to: server, member: member)
        } catch {
            Self.logger.error("The upload failed: \(String(describing: error), privacy: .public)")
        }
        guard downloads else { return }
        do {
            try await download(from: server, member: member)
        } catch {
            Self.logger.error("The download failed: \(String(describing: error), privacy: .public)")
        }
        do {
            packMembers = try await server.packMembers()
        } catch {
            Self.logger.error("The members cannot be read: \(String(describing: error), privacy: .public)")
        }
    }

    private func upload(to server: any Server, member: ServerMember) async throws {
        if isMemberNameWaitingToUpload {
            let name = memberName
            try await server.renameMember(to: name)
            if memberName == name {
                isMemberNameWaitingToUpload = false
            }
        } else {
            memberName = member.name
        }
        if let packID = try await uploadPack(to: server, member: member) {
            try await PackUpload(context: context, server: server, packID: packID, uploadedFiles: uploadedFiles)
                .run()
        }
    }

    /// Downloads the changes of the pack of the account. A phone without a
    /// pack gets the pack of the account. A phone whose pack is another pack
    /// downloads nothing, because its dogs first have to move into the pack
    /// of the account (ADR 0005).
    private func download(from server: any Server, member: ServerMember) async throws {
        guard let packID = member.packID else { return }
        if let pack = try context.fetch(Pack.all()).first, pack.id != packID { return }
        try await PackDownload(
            context: context, server: server, packID: packID, uploadedFiles: uploadedFiles, cursors: downloadCursors
        ).run()
    }

    /// Uploads the pack of the phone when it has changed. When the account
    /// is already in another pack, the dogs of the phone first move into that
    /// pack (ADR 0005). When the person has left the pack of the phone, or
    /// the pack owner has removed them, the phone deletes it.
    ///
    /// It returns the ID of the pack when the pack of the phone is on the
    /// server, or nil.
    private func uploadPack(to server: any Server, member: ServerMember) async throws -> UUID? {
        guard let pack = try context.fetch(Pack.all()).first else {
            packOfAccount = nil
            return nil
        }
        if member.packID != pack.id, try await server.hasLeftPack(pack.id) {
            try deletePackAfterDeparture()
            packOfAccount = nil
            return nil
        }
        if let packID = member.packID, packID != pack.id {
            return try await moveDogs(of: pack, into: packID, on: server)
        }
        packOfAccount = nil
        if member.packID == nil, !pack.isWaitingToUpload {
            pack.isWaitingToUpload = true
            try noteRowsWaiting()
        }
        guard pack.isWaitingToUpload else { return member.packID }
        let changedAt = pack.changedAt
        if member.packID == nil {
            try await server.createPack(id: pack.id, name: pack.name, createdAt: pack.createdAt)
        } else {
            try await server.renamePack(id: pack.id, to: pack.name)
        }
        // A change during the upload uploads the next time.
        if pack.changedAt == changedAt {
            pack.isWaitingToUpload = false
            try context.save()
        }
        return pack.id
    }

    /// Moves the dogs of the pack of the phone into the pack of the account,
    /// and deletes the pack of the phone. The dogs move when the person has
    /// agreed, or when the pack of the phone has moved on the server already,
    /// because the person joined from another phone. Otherwise they wait for
    /// a confirmation (`packOfAccount`).
    ///
    /// It returns the ID of the pack of the account after the move, or nil.
    private func moveDogs(of pack: Pack, into packID: UUID, on server: any Server) async throws -> UUID? {
        let isAgreed = agreedMove == PackMove(pack: pack.id, into: packID)
        let hasMoved = try await server.hasMovedIntoPackOfAccount(pack: pack.id)
        guard let serverPack = try await server.pack(id: packID) else { return nil }
        guard isAgreed || hasMoved else {
            packOfAccount = serverPack
            return nil
        }
        let newPack = try PackDownload.storePack(serverPack, in: context)
        newPack.deletedAt = nil
        for dog in pack.dogs ?? [] {
            dog.pack = newPack
        }
        context.delete(pack)
        // A pack that moved on the server has its rows in the new pack, and
        // its files stay where the members of the new pack read them. So only
        // the rows that wait upload. The rows of a pack that the server has
        // not moved upload again into the new pack, with their files.
        if !hasMoved {
            try noteRowsWaiting()
        }
        try context.save()
        agreedMove = nil
        packOfAccount = nil
        return packID
    }

    /// Deletes the pack of this phone, with its dogs, their walks and their
    /// completed records, because the person is out of the pack. The person
    /// is a member of at most one pack (ADR 0005), so the phone keeps no
    /// such row. A walk that this phone records keeps the pack until it
    /// ends, and the next download deletes it then.
    private func deletePackAfterDeparture() throws {
        guard try context.fetchCount(Self.unfinishedWalks) == 0 else { return }
        func deleteAll<Row: UploadingRow>(_ type: Row.Type) throws {
            for row in try context.fetch(FetchDescriptor<Row>()) {
                context.delete(row)
            }
        }
        try deleteAll(CompletedArea.self)
        try deleteAll(CompletedStreet.self)
        try deleteAll(WalkDog.self)
        try deleteAll(Walk.self)
        try deleteAll(Dog.self)
        try deleteAll(Pack.self)
        try context.save()
        agreedMove = nil
        uploadedFiles.forgetAll()
        downloadCursors.forgetAll()
    }

    /// The walks that are still being recorded.
    private static var unfinishedWalks: FetchDescriptor<Walk> {
        FetchDescriptor(predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil })
    }

    /// Notes that every row and file of the phone waits to upload again, for
    /// example because the server lost the pack.
    private func noteRowsWaiting() throws {
        func noteWaiting<Row: UploadingRow>(_ type: Row.Type) throws {
            for row in try context.fetch(FetchDescriptor<Row>()) {
                row.isWaitingToUpload = true
            }
        }
        try noteWaiting(Dog.self)
        try noteWaiting(Walk.self)
        try noteWaiting(WalkDog.self)
        try noteWaiting(CompletedArea.self)
        try noteWaiting(CompletedStreet.self)
        try context.save()
        uploadedFiles.forgetAll()
    }

    private func changeMemberName(to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != memberName else { return }
        memberName = name
        isMemberNameWaitingToUpload = true
        countWaitingChanges()
    }
}

/// What Sign in with Apple gives the app.
struct AppleCredential {
    var idToken: String
    /// The nonce. Apple gets only its hash.
    var nonce: String
    /// The given name of the person, which Apple gives only at the first
    /// sign-in.
    var givenName: String?
}

extension Account {
    /// An account without a server, for previews.
    static let preview = Account(server: nil, context: .preview)
}

/// Why the account cannot sign in.
enum AccountError: Error {
    /// The build has no Supabase keys.
    case noServer
    /// The person has not signed in.
    case notSignedIn
}
