//
//  PackStorageNote.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 07.10.2026.
//

import SwiftUI

/// The note that the walks of a pack cannot upload, because the iCloud
/// storage of the pack owner is full (`Packs.storageNote(of:)`). It shows
/// nothing while the pack uploads. The pack section of the settings and the
/// walk list show it.
struct PackStorageNote: View {
    @ObservedObject var pack: Pack

    @Environment(Packs.self) private var packs

    var body: some View {
        if let note = packs.storageNote(of: pack) {
            Label(note, systemImage: "exclamationmark.icloud")
                .foregroundStyle(.secondary)
        }
    }
}
