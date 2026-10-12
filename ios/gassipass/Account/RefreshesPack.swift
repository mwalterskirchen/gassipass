//
//  RefreshesPack.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 12.10.2026.
//

import SwiftUI

extension View {
    /// Pull to refresh uploads the changes of this phone and downloads the
    /// changes of the other phones of the pack. Without an account the list
    /// has no pull to refresh.
    func refreshesPack() -> some View {
        modifier(RefreshesPack())
    }
}

private struct RefreshesPack: ViewModifier {
    @Environment(Account.self) private var account

    func body(content: Content) -> some View {
        if account.isSignedIn {
            content.refreshable {
                await account.refresh()
            }
        } else {
            content
        }
    }
}
