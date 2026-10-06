//
//  PackInvitation.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 06.10.2026.
//

import CloudKit
import CoreTransferable
import UIKit

/// The invitation to a pack, which the share sheet sends as a CloudKit share
/// link. A pack that has a share sends that share again, and a pack without
/// a share gets one when the pack owner picks how to send the link.
nonisolated struct PackInvitation: Transferable, Sendable {
    /// The share of the pack, or nil when the pack was never shared.
    let share: CKShare?
    /// Makes the share of the pack (`Packs.shareForInvitation(to:)`).
    let makeShare: @Sendable () async throws -> CKShare

    /// Members can read and change everything in the pack, and only the
    /// people who get the link can join.
    static let sharingOptions = CKAllowedSharingOptions(
        allowedParticipantPermissionOptions: .readWrite, allowedParticipantAccessOptions: .specifiedRecipientsOnly)

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { invitation in
            let container = CKContainer(identifier: Stores.cloudKitContainerIdentifier)
            if let share = invitation.share {
                return .existing(share, container: container, allowedSharingOptions: sharingOptions)
            }
            return .prepareShare(
                container: container, allowedSharingOptions: sharingOptions, preparationHandler: invitation.makeShare)
        }
    }
}

/// Starts the app with a scene delegate that accepts the share links of
/// invitations.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = InvitationSceneDelegate.self
        return configuration
    }
}

/// Accepts the share link of an invitation that the person tapped. iOS
/// gives the link to a running app, or to the scene of an app that the link
/// launches.
final class InvitationSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// The packs of the app. The app sets them before iOS connects a scene.
    static var packs: Packs?

    func scene(
        _ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            accept(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        accept(metadata)
    }

    private func accept(_ metadata: CKShare.Metadata) {
        guard let packs = Self.packs else { return }
        Task {
            await packs.accept(metadata)
        }
    }
}
