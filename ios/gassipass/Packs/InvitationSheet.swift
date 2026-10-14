//
//  InvitationSheet.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 14.10.2026.
//

import SwiftData
import SwiftUI

extension View {
    /// Opens an invitation link (`InvitationLink`) in a sheet, where the
    /// person joins the pack after a confirmation.
    func opensInvitations() -> some View {
        modifier(OpensInvitations())
    }
}

private struct OpensInvitations: ViewModifier {
    @State private var opened: OpenedInvitation?

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                if let token = InvitationLink.token(in: url) {
                    opened = OpenedInvitation(token: token)
                }
            }
            .sheet(item: $opened) { invitation in
                InvitationSheet(token: invitation.token)
            }
    }
}

private struct OpenedInvitation: Identifiable {
    let id = UUID()
    let token: String
}

/// An invitation to a pack. A person without an account signs in first. The
/// server then says whether the person can join, and the person joins after
/// a confirmation, which names the dogs that come along (ADR 0005). The
/// phone then downloads the pack.
private struct InvitationSheet: View {
    let token: String

    @Environment(Account.self) private var account
    @Query(Dog.all()) private var dogs: [Dog]
    @Query(Pack.all()) private var ownPacks: [Pack]
    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.checking

    private enum Phase {
        case checking
        /// The invitation with the state of the check, or with the answer
        /// of the join: joined, or the state that keeps the person out.
        case checked(Invitation)
        case joining(Invitation)
        case failed
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Invitation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", role: .cancel) {
                            dismiss()
                        }
                    }
                }
        }
        .task(id: account.isSignedIn) {
            if account.isSignedIn {
                await check()
            }
        }
    }

    @ViewBuilder private var content: some View {
        if !account.isSignedIn {
            ContentUnavailableView {
                Label("Join a Pack", systemImage: "person.2")
            } description: {
                Text("Sign in to join the pack. In the pack, you see the dogs and walks of the other members, and they see yours.")
            } actions: {
                SignInButton()
                    .frame(maxWidth: 280)
            }
        } else {
            switch phase {
            case .checking:
                ProgressView()
            case .checked(let invitation):
                switch invitation.state {
                case .open:
                    confirmation(of: invitation, isJoining: false)
                case .joined:
                    ContentUnavailableView {
                        Label("Welcome to the Pack", systemImage: "checkmark.circle")
                    } description: {
                        Text("You are now a member of the pack «\(packName(of: invitation))». Its dogs and walks now come to your phone.")
                    } actions: {
                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                default:
                    refusal(of: invitation)
                }
            case .joining(let invitation):
                confirmation(of: invitation, isJoining: true)
            case .failed:
                ContentUnavailableView {
                    Label("No Connection", systemImage: "wifi.slash")
                } description: {
                    Text("The invitation cannot be opened. Please check the connection and try again.")
                } actions: {
                    Button("Try Again") {
                        Task {
                            await check()
                        }
                    }
                }
            }
        }
    }

    private func confirmation(of invitation: Invitation, isJoining: Bool) -> some View {
        ContentUnavailableView {
            Label("Join the Pack?", systemImage: "person.2")
        } description: {
            Text(verbatim: [
                invitationText(of: invitation),
                String(localized: "In the pack, you see the dogs and walks of the other members, and they see yours."),
                dogsText,
            ].compactMap(\.self).joined(separator: " "))
        } actions: {
            Button {
                join(invitation)
            } label: {
                if isJoining {
                    ProgressView()
                } else {
                    Text("Join Pack")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isJoining)
        }
    }

    private func refusal(of invitation: Invitation) -> some View {
        let (title, symbol, text): (LocalizedStringKey, String, LocalizedStringKey) =
            switch invitation.state {
            case .member:
                ("Already in This Pack", "person.2",
                 "You are already a member of the pack «\(packName(of: invitation))».")
            case .used:
                ("Invitation Used", "envelope.open",
                 "Somebody has already joined with this invitation. An invitation works only once. Ask the pack owner for a new one.")
            case .expired:
                ("Invitation Expired", "clock",
                 "An invitation works for 7 days. Ask the pack owner for a new one.")
            case .inOtherPack:
                ("Already in a Pack", "person.2.slash",
                 "You are already a member of a pack with other members, and a person can be a member of only one pack.")
            case .open, .joined, .unknown:
                ("Invitation Not Found", "questionmark.circle",
                 "This invitation does not exist. Ask the pack owner for a new one.")
            }
        return ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(text)
        }
    }

    /// Who invites the person into which pack.
    private func invitationText(of invitation: Invitation) -> String {
        switch (invitation.packOwnerName.isEmpty, invitation.packName.isEmpty) {
        case (false, false):
            String(localized: "\(invitation.packOwnerName) invites you into the pack «\(invitation.packName)».")
        case (false, true):
            String(localized: "\(invitation.packOwnerName) invites you into their pack.")
        case (true, false):
            String(localized: "You are invited into the pack «\(invitation.packName)».")
        case (true, true):
            String(localized: "You are invited into a pack.")
        }
    }

    /// The dogs of this phone that come along into the pack, or nil for a
    /// person without dogs.
    private var dogsText: String? {
        guard !dogs.isEmpty else { return nil }
        let names = dogs.map(\.name).formatted(.list(type: .and))
        let ownPackName = ownPacks.first?.shownName ?? Pack.defaultName
        return String(localized: "You bring \(names) into the pack, with all walks and stamps. Your pack «\(ownPackName)» then disappears.")
    }

    private func packName(of invitation: Invitation) -> String {
        Pack.shownName(invitation.packName)
    }

    private func check() async {
        phase = .checking
        do {
            phase = .checked(try await account.checkInvitation(token: token))
        } catch {
            phase = .failed
        }
    }

    private func join(_ invitation: Invitation) {
        phase = .joining(invitation)
        Task {
            do {
                var answered = invitation
                answered.state = try await account.join(token: token)
                phase = .checked(answered)
            } catch {
                phase = .failed
            }
        }
    }
}
