//
//  PackMemberRows.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 14.10.2026.
//

import SwiftUI
import UIKit

/// The members of the pack in the «Rudel» section, «Mitglied einladen» for
/// the pack owner, and «Rudel verlassen» for a member who is not the pack
/// owner. The pack owner removes a member with a swipe on their row. The
/// members load with each download, so a person without an account sees no
/// members.
struct PackMemberRows: View {
    @Environment(Account.self) private var account
    let pack: Pack

    @State private var isMakingInvitation = false
    @State private var invitationFailed = false
    /// The member whom the pack owner wants to remove, until they confirm.
    @State private var memberToRemove: PackMember?
    @State private var removalFailed = false
    @State private var isConfirmingLeave = false
    @State private var isLeaving = false
    @State private var leaveFailed = false

    var body: some View {
        ForEach(account.packMembers) { member in
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
            .swipeActions {
                if account.isPackOwner && !member.isThisPerson {
                    Button("Remove", role: .destructive) {
                        memberToRemove = member
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove \(memberToRemove.map(shownName(of:)) ?? "")?", isPresented: isConfirmingRemoval,
            titleVisibility: .visible, presenting: memberToRemove
        ) { member in
            Button("Remove", role: .destructive) {
                remove(member)
            }
        } message: { member in
            Text("\(shownName(of: member)) no longer sees the pack. The walks of \(shownName(of: member)) stay with the dogs.")
        }
        .alert("Not Removed", isPresented: $removalFailed) {
        } message: {
            Text("The member cannot be removed. Please check the connection and try again.")
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
        if account.canLeavePack {
            Button("Leave Pack", role: .destructive) {
                isConfirmingLeave = true
            }
            .disabled(isLeaving)
            .confirmationDialog("Leave Pack?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
                Button("Leave Pack", role: .destructive) {
                    leave()
                }
            } message: {
                Text("The pack «\(pack.shownName)» and its dogs disappear from this phone. Your walks stay with the dogs in the pack.")
            }
            .alert("Still in the Pack", isPresented: $leaveFailed) {
            } message: {
                Text("You cannot leave the pack now. Please check the connection and try again.")
            }
        }
    }

    private var isConfirmingRemoval: Binding<Bool> {
        Binding {
            memberToRemove != nil
        } set: { isPresented in
            if !isPresented {
                memberToRemove = nil
            }
        }
    }

    private func remove(_ member: PackMember) {
        Task {
            do {
                try await account.removeMember(member)
            } catch {
                removalFailed = true
            }
        }
    }

    private func leave() {
        isLeaving = true
        Task {
            defer { isLeaving = false }
            do {
                try await account.leavePack()
            } catch {
                leaveFailed = true
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
