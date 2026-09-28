//
//  OrderMenu.swift
//  doggo
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import SwiftUI

/// A menu that sorts the areas of the collection book and the streets of an
/// area by name or by completion. Both screens share the choice, and it stays
/// when the app starts again.
struct OrderMenu: View {
    @AppStorage(Self.key) private var order: CollectionBook.Order = Self.defaultOrder

    /// The key of the stored choice. Screens read the choice with it.
    static let key = "collectionOrder"
    /// The order before the user makes a choice: the most completed first.
    static let defaultOrder = CollectionBook.Order.completion

    var body: some View {
        Menu("Sort", systemImage: "arrow.up.arrow.down") {
            Picker("Sort", selection: $order) {
                Text("Name").tag(CollectionBook.Order.name)
                Text("Completion").tag(CollectionBook.Order.completion)
            }
        }
    }
}
