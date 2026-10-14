//
//  InvitationLink.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 14.10.2026.
//

import Foundation

/// The link of an invitation: `https://gassipass.ch/invitation/<token>`. The
/// token is the secret of the link, which the server makes. The website
/// lets the link open the app (see `web/` and the README).
nonisolated enum InvitationLink {
    private static let host = "gassipass.ch"
    private static let folder = "invitation"

    /// The link with the token.
    static func url(token: String) -> URL {
        URL(string: "https://\(host)/\(folder)/\(token)")!
    }

    /// The token in the link, or nil for a link that is no invitation.
    static func token(in url: URL) -> String? {
        guard url.scheme == "https", url.host() == host else { return nil }
        let components = url.pathComponents
        guard components.count == 3, components[1] == folder else { return nil }
        let token = components[2]
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard token.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return token
    }
}
