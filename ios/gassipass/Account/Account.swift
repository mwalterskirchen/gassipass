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
/// the member name and the pack of the phone upload to the server. Without
/// an account, the app makes no request to the server.
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

    /// Whether the member name has changed since its last upload.
    @ObservationIgnored private var isMemberNameWaiting: Bool {
        get { defaults.bool(forKey: Self.memberNameWaitingKey) }
        set { defaults.set(newValue, forKey: Self.memberNameWaitingKey) }
    }

    @ObservationIgnored private let server: (any Server)?
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let defaults: UserDefaults

    private static let memberNameKey = "memberName"
    private static let memberNameWaitingKey = "memberNameIsWaitingToUpload"
    private static let logger = Logger(subsystem: "ch.mwalterskirchen.gassipass", category: "Account")

    /// - Parameter server: The server, or nil when the build has no
    ///   Supabase keys. Then nobody can sign in.
    init(server: (any Server)?, context: ModelContext, defaults: UserDefaults = .standard) {
        self.server = server
        self.context = context
        self.defaults = defaults
        isSignedIn = server?.isSignedIn ?? false
        memberName = defaults.string(forKey: Self.memberNameKey) ?? ""
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
        try await server.signIn(appleIDToken: credential.idToken, nonce: credential.nonce)
        isSignedIn = true
        if let givenName = credential.givenName {
            changeMemberName(to: givenName)
        }
        await upload()
    }

    /// Gives the member a new name, and uploads it.
    func renameMember(to name: String) async {
        changeMemberName(to: name)
        await upload()
    }

    /// Uploads what has changed: the member name and the pack. A failed
    /// upload is logged, and the next upload tries again.
    func upload() async {
        guard let server, isSignedIn else { return }
        do {
            let member = try await server.member()
            if isMemberNameWaiting {
                let name = memberName
                try await server.renameMember(to: name)
                if memberName == name {
                    isMemberNameWaiting = false
                }
            } else {
                memberName = member.name
            }
            try await uploadPack(to: server, member: member)
        } catch {
            Self.logger.error("The upload failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Uploads the pack of the phone when it has changed. A person whose
    /// account is already in another pack uploads nothing, because the dogs
    /// of the phone first have to move into that pack (ADR 0005).
    private func uploadPack(to server: any Server, member: ServerMember) async throws {
        guard let pack = try context.fetch(Pack.all()).first, pack.isWaitingToUpload else { return }
        let changedAt = pack.changedAt
        switch member.packID {
        case nil:
            try await server.createPack(id: pack.id, name: pack.name, createdAt: pack.createdAt)
        case pack.id:
            try await server.renamePack(id: pack.id, to: pack.name)
        default:
            return
        }
        // A change during the upload uploads the next time.
        if pack.changedAt == changedAt {
            pack.isWaitingToUpload = false
            try context.save()
        }
    }

    private func changeMemberName(to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != memberName else { return }
        memberName = name
        isMemberNameWaiting = true
    }
}

/// What Sign in with Apple gives the app.
struct AppleCredential {
    var idToken: String
    /// The nonce, before its hash went to Apple.
    var nonce: String
    /// The given name of the person, which Apple gives only at the first
    /// sign-in.
    var givenName: String?
}

extension Account {
    /// An account without a server, for previews.
    static let preview = Account(server: nil, context: .preview)
}

enum AccountError: Error {
    /// The build has no Supabase keys.
    case noServer
}
