//
//  NameField.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 14.10.2026.
//

import SwiftUI

/// A text field for a name. The new name counts when the person leaves the
/// field. While the person edits, a change from elsewhere, for example from
/// a download, does not replace the text.
struct NameField: View {
    private let title: LocalizedStringKey
    private let prompt: Text?
    private let name: String
    private let save: (String) -> Void

    @State private var text = ""
    /// The name when the field last showed it, so that only an edit in the
    /// field saves.
    @State private var shownName = ""
    @FocusState private var isFocused: Bool

    /// - Parameters:
    ///   - name: The stored name.
    ///   - save: Saves the new name.
    init(_ title: LocalizedStringKey, prompt: Text? = nil, name: String, save: @escaping (String) -> Void) {
        self.title = title
        self.prompt = prompt
        self.name = name
        self.save = save
    }

    var body: some View {
        TextField(title, text: $text, prompt: prompt)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .focused($isFocused)
            .onAppear {
                show(name)
            }
            .onChange(of: name) {
                if !isFocused {
                    show(name)
                }
            }
            .onChange(of: isFocused) {
                if !isFocused {
                    commit()
                }
            }
            .onDisappear(perform: commit)
    }

    private func commit() {
        guard text != shownName else { return }
        shownName = text
        save(text)
    }

    private func show(_ name: String) {
        text = name
        shownName = name
    }
}
