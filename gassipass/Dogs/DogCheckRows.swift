//
//  DogCheckRows.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import SwiftData
import SwiftUI

/// One row for each dog, which the walker taps to choose the dog for a walk
/// or to remove it again.
struct DogCheckRows: View {
    let dogs: [Dog]
    @Binding var chosen: Set<PersistentIdentifier>

    var body: some View {
        ForEach(dogs) { dog in
            let isChosen = chosen.contains(dog.persistentModelID)
            Button {
                if isChosen {
                    chosen.remove(dog.persistentModelID)
                } else {
                    chosen.insert(dog.persistentModelID)
                }
            } label: {
                HStack(spacing: 14) {
                    DogBadge(dog: dog, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dog.name)
                            .foregroundStyle(Color.primary)
                        if dog.isRetired {
                            Text("Retired")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isChosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isChosen ? .isSelected : [])
            }
        }
    }
}
