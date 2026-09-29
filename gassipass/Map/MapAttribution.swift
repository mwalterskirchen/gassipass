//
//  MapAttribution.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import SwiftUI

/// The source reference that swisstopo requires for its data and for the
/// light base map. The map shows it at all times.
///
/// The swisstopo credits come from the terms of the base map:
/// https://www.swisstopo.admin.ch/en/web-maps-base-map
/// The light base map uses OpenMapTiles data outside Switzerland, so it also
/// needs the MapTiler and OpenStreetMap credits:
/// https://www.swisstopo.admin.ch/en/web-maps-light-base-map
struct MapAttribution: View {
    static let text =
        "© swisstopo, © FDFA, © FOEN, © FOCP, © SAC, © Naturefriends Switzerland, "
        + "© opentransportdata.swiss, © MapTiler, © OpenStreetMap contributors"

    var body: some View {
        Text(Self.text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: .rect(cornerRadius: 4))
    }
}
