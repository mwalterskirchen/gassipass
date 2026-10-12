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

    /// Uploads the pack of the phone when it has changed. A person whose
    /// account is already in another pack uploads nothing, because the dogs
    /// of the phone first have to move into that pack (ADR 0005).
    ///
    /// It returns the ID of the pack when the pack of the phone is on the
    /// server, or nil.
    private func uploadPack(to server: any Server, member: ServerMember) async throws -> UUID? {
        guard let pack = try context.fetch(Pack.all()).first else { return nil }
        if member.packID == nil, !pack.isWaitingToUpload {
            try noteEverythingWaiting()
        }
        guard pack.isWaitingToUpload else { return member.packID == pack.id ? pack.id : nil }
        let changedAt = pack.changedAt
        switch member.packID {
        case nil:
            try await server.createPack(id: pack.id, name: pack.name, createdAt: pack.createdAt)
        case pack.id:
            try await server.renamePack(id: pack.id, to: pack.name)
        default:
            return nil
        }
        // A change during the upload uploads the next time.
        if pack.changedAt == changedAt {
            pack.isWaitingToUpload = false
            try context.save()
        }
        return pack.id
    }

    /// The pack of the phone has uploaded, but the account has no pack, for
    /// example because the server lost it. So every row and file of the
    /// phone waits to upload again.
    private func noteEverythingWaiting() throws {
        func noteWaiting<Row: UploadingRow>(_ type: Row.Type) throws {
            for row in try context.fetch(FetchDescriptor<Row>()) {
                row.isWaitingToUpload = true
            }
        }
        try noteWaiting(Pack.self)
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
}
