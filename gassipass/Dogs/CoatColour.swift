//
//  CoatColour.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import SwiftUI

/// The colour of a dog's coat. The badge of a dog without a photo shows it,
/// so that the dogs look different on a walk with several dogs.
nonisolated enum CoatColour: String, CaseIterable, Identifiable, Sendable {
    case apricot, cream, red, chocolate, black, grey

    var id: Self { self }

    /// The coat colour for a new dog: the first one that none of the other
    /// dogs has, else apricot.
    static func forNewDog(besides others: [CoatColour]) -> CoatColour {
        allCases.first { !others.contains($0) } ?? .apricot
    }

    var name: LocalizedStringResource {
        switch self {
        case .apricot: "Apricot"
        case .cream: "Cream"
        case .red: "Red"
        case .chocolate: "Chocolate"
        case .black: "Black"
        case .grey: "Grey"
        }
    }

    var color: Color {
        switch self {
        case .apricot: Color(red: 0xED / 255, green: 0xA5 / 255, blue: 0x67 / 255)
        case .cream: Color(red: 0xF1 / 255, green: 0xDF / 255, blue: 0xBE / 255)
        case .red: Color(red: 0xB8 / 255, green: 0x56 / 255, blue: 0x2E / 255)
        case .chocolate: Color(red: 0x6B / 255, green: 0x44 / 255, blue: 0x2A / 255)
        case .black: Color(red: 0x2E / 255, green: 0x2A / 255, blue: 0x27 / 255)
        case .grey: Color(red: 0xA3 / 255, green: 0xA1 / 255, blue: 0x9E / 255)
        }
    }

    /// The colour of the letter on the badge: dark on a light coat, white
    /// on a dark coat.
    var letterColor: Color {
        switch self {
        case .apricot, .cream, .grey: Color(red: 0x3B / 255, green: 0x24 / 255, blue: 0x12 / 255)
        case .red, .chocolate, .black: .white
        }
    }
}
