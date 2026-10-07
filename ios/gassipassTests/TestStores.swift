//
//  TestStores.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 05.10.2026.
//

import SwiftData
@testable import gassipass

extension ModelContainer {
    /// A second context on the store, which sees only what was saved.
    func newContext() -> ModelContext {
        ModelContext(self)
    }
}

extension ModelContext {
    /// All rows of the model, with the values that are in the store now.
    func fetchAll<Model: PersistentModel>(_ type: Model.Type) throws -> [Model] {
        try fetch(FetchDescriptor<Model>())
    }
}
