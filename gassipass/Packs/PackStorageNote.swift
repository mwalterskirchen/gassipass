//
//  PackStorageNote.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 07.10.2026.
//

import SwiftUI

/// The note that the walks of a pack cannot upload, because the iCloud
/// storage of the pack owner is full. It names the pack owner, and shows
/// nothing while the pack uploads. The "Rudel" section of the settings and
/// the walk list show it.
struct PackStorageNote: View {
    @ObservedObject var pack: Pack

    @Environment(Packs.self) private var packs

    var body: some View {
        if packs.isStorageFull(of: pack) {
            Label(message, systemImage: "exclamationmark.icloud")
                .foregroundStyle(.secondary)
        }
    }

    private var message: String {
        let packName = packs.shownName(of: pack)
        if packs.isPackOwner(of: pack) {
            return String(localized: "Your iCloud storage is full. Walks of “\(packName)” stay on this iPhone and upload when there is space again.")
        }
        guard let packOwnerName = packs.packOwnerName(of: pack) else {
            return String(localized: "The iCloud storage of the pack owner is full. Walks of “\(packName)” stay on this iPhone and upload when there is space again.")
        }
        return String(localized: "The iCloud storage of \(packOwnerName) is full. Walks of “\(packName)” stay on this iPhone and upload when there is space again.")
    }
}
