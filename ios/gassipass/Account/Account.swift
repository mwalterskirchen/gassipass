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
/// soon after it is saved. Without an account, the app makes no request to
/// the server.
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

    @ObservationIgnored private var isUploading = false
    /// Whether a call came during the running upload.
    @ObservationIgnored private var uploadsAgain = false
    /// The number of waiting changes after the last upload, when it failed.
    /// Until a new change waits, a save does not start another upload, so a
    /// row that keeps failing does not upload at each save of a walk.
    @ObservationIgnored private var waitingAfterFailure: Int?

    @ObservationIgnored private let server: (any Server)?
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let uploadedFiles: UploadedFiles

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
        isSignedIn = server?.isSignedIn ?? false
        memberName = defaults.string(forKey: Self.memberNameKey) ?? ""
        countWaitingChanges()
    }

    /// Whether this build can sign in.
    var canSignIn: Bool {
        server != nil
    }

    /// Signs in with Sign in with Apple, and uploads. Apple gives the name
    /// of the person only at their first sign-in, and it becomes the member
    /// name.
    func signIn(with credential: AppleCredential) async throws {
        guard let server else { throw AccountError.noServer }
        // The phone keeps the name before the request, because a failed
        // sign-in does not get it again.
        if let givenName = credential.givenName {
            changeMemberName(to: givenName)
        }
        try await server.signIn(appleIDToken: credential.idToken, nonce: credential.nonce)
        isSignedIn = true
        await upload()
    }

    /// Gives the member a new name, and uploads it.
    func renameMember(to name: String) async {
        changeMemberName(to: name)
        await upload()
    }

    /// Uploads what has changed: the member name, the pack and its rows. A
    /// failed upload is logged, and the next upload tries again.
    ///
    /// Only one upload runs at a time. A call during an upload makes the
    /// running upload start again when it ends, so that the newest change
    /// reaches the server last.
    func upload() async {
        guard let server, isSignedIn else { return }
        guard !isUploading else {
            uploadsAgain = true
            return
        }
        isUploading = true
        defer {
            isUploading = false
        }
        var succeeded: Bool
        repeat {
            uploadsAgain = false
            succeeded = await uploadOnce(to: server)
        } while uploadsAgain
        countWaitingChanges()
        waitingAfterFailure = succeeded ? nil : waitingChanges
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

    private func changesSaved() async {
        countWaitingChanges()
        guard waitingChanges > (waitingAfterFailure ?? 0) else { return }
        await upload()
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

    /// Uploads once, and returns whether everything uploaded.
    private func uploadOnce(to server: any Server) async -> Bool {
        do {
            let member = try await server.member()
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
            return true
        } catch {
            Self.logger.error("The upload failed: \(String(describing: error), privacy: .public)")
            return false
        }
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
