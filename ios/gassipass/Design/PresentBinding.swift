//
//  PresentBinding.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 14.10.2026.
//

import SwiftUI

extension Binding where Value == Bool {
    /// Whether the optional has a value, for an alert or a dialog that
    /// presents it. Closing the alert or dialog sets the optional to nil.
    init<Wrapped>(isPresent optional: Binding<Wrapped?>) {
        self.init {
            optional.wrappedValue != nil
        } set: { isPresented in
            if !isPresented {
                optional.wrappedValue = nil
            }
        }
    }
}
