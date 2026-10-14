//
//  PackMemberRows.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 14.10.2026.
//

import SwiftUI
import UIKit

/// The members of the pack in the «Rudel» section, and «Mitglied einladen»
/// for the pack owner. The members load with each download, so a person
/// without an account sees no members.
struct PackMemberRows: View {
    @Environment(Account.self) private var account
    let pack: Pack

    @State private var isMakingInvitation = false
    @State private var invitationFailed = false

    var body: some View {
        ForEach(Array(account.packMembers.enumerated()), id: \.offset) { _, member in
            LabeledContent {
                if member.isPackOwner {
                    Text("Pack Owner")
                }
            } label: {
                if member.isThisPerson {
                    Text("\(shownName(of: member)) (You)")
                } else {
                    Text(shownName(of: member))
                }
            }
        }
        if account.isPackOwner {
            Button {
                invite()
            } label: {
                Label("Invite Member", systemImage: "person.badge.plus")
            }
            .disabled(isMakingInvitation)
            .alert("No Invitation", isPresented: $invitationFailed) {
            } message: {
                Text("The invitation cannot be made. Please check the connection and try again.")
            }
        }
    }

    private func shownName(of member: PackMember) -> String {
        member.name.isEmpty ? String(localized: "Member Without a Name") : member.name
    }

    /// Makes an invitation, and opens the share sheet with its link.
    private func invite() {
        isMakingInvitation = true
        Task {
            defer { isMakingInvitation = false }
            do {
                let link = try await account.makeInvitationLink()
                let message = String(localized: "Join my pack «\(pack.shownName)» in GassiPass.")
                ShareSheet.present([message, link])
            } catch {
                invitationFailed = true
            }
        }
    }
}

/// The share sheet of iOS, over the screen at the front.
private enum ShareSheet {
    static func present(_ items: [Any]) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var front = scene?.keyWindow?.rootViewController else { return }
        while let presented = front.presentedViewController {
            front = presented
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // An iPad shows the share sheet as a popover, which needs a place.
        controller.popoverPresentationController?.sourceView = front.view
        controller.popoverPresentationController?.sourceRect = CGRect(
            x: front.view.bounds.midX, y: front.view.bounds.midY, width: 0, height: 0)
        front.present(controller, animated: true)
    }
}
