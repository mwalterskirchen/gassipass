//
//  Collections+Preview.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 27.09.2026.
//

import Foundation
import SwiftData

extension Collections {
    /// Collections with an empty store and no map packages, for previews.
    public static func preview(context: ModelContext = .preview) -> Collections {
        Collections(context: context, packages: MapPackages(urls: []), cacheRoot: nil)
    }
}

extension ModelContainer {
    /// An empty in-memory store, for previews.
    public static let preview = try! LocalStore.inMemory()
}

extension ModelContext {
    /// The context of the store for previews.
    public static var preview: ModelContext {
        ModelContainer.preview.mainContext
    }
}
