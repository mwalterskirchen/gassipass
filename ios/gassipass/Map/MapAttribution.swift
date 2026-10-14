//
//  MapAttribution.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// The source reference that swisstopo requires for its data and for the
/// light base map. The map shows "© swisstopo" at all times, and the info
/// button next to it shows the full attribution.
///
/// The swisstopo credits come from the terms of the base map:
/// https://www.swisstopo.admin.ch/en/web-maps-base-map
/// The light base map uses OpenMapTiles data outside Switzerland, so it also
/// needs the MapTiler and OpenStreetMap credits:
/// https://www.swisstopo.admin.ch/en/web-maps-light-base-map
/// The OpenStreetMap guidelines allow these credits behind an info button in
/// the corner of the map:
/// https://osmfoundation.org/wiki/Licence/Attribution_Guidelines
struct MapAttribution: View {
    static let shortText = "© swisstopo"
    /// The offices and clubs have other names in other languages, for
    /// example FDFA is EDA in German.
    static let text: LocalizedStringResource =
        "© swisstopo, © FDFA, © FOEN, © FOCP, © SAC, © Naturefriends Switzerland, © opentransportdata.swiss, © MapTiler, © OpenStreetMap contributors"

    @State private var showsFullText = false

    var body: some View {
        Button {
            showsFullText = true
        } label: {
            HStack(spacing: 4) {
                Text(Self.shortText)
                Image(systemName: "info.circle")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: .rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map data \(Self.shortText)")
        .accessibilityHint("Shows all map credits")
        .popover(isPresented: $showsFullText) {
            Text(Self.text)
                .font(.footnote)
                .padding()
                .frame(idealWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
        }
    }
}
