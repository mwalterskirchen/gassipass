//
//  PassportIdentity.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 25.10.2026.
//

import Foundation

/// What the identity page of the passport shows about a dog: its name, its
/// date of birth, its age, and the issue date of the passport.
///
/// A dog that takes part in walks shows its age. A retired dog shows its
/// date of birth and its retirement date, and no age, because a dog that has
/// died must not keep getting older.
nonisolated struct PassportIdentity: Equatable {
    /// The age of a dog: whole years from its first birthday, else whole
    /// months, else whole weeks.
    enum Age: Equatable {
        case years(Int)
        case months(Int)
        case weeks(Int)
    }

    let id: UUID
    let name: String
    let bornOn: Date?
    let retiredAt: Date?
    /// The issue date: the time when a member added the dog to the app.
    let issuedAt: Date?
    /// The age today, or nil for a retired dog or an unknown date of birth.
    let age: Age?

    init(id: UUID, name: String, bornOn: Date?, retiredAt: Date?, addedAt: Date?, now: Date) {
        self.id = id
        self.name = name
        self.bornOn = bornOn
        self.retiredAt = retiredAt
        self.issuedAt = addedAt
        age = retiredAt == nil ? bornOn.flatMap { Self.age(bornOn: $0, now: now) } : nil
    }

    init(dog: Dog, now: Date) {
        self.init(
            id: dog.id, name: dog.name, bornOn: dog.bornOn, retiredAt: dog.retiredAt, addedAt: dog.addedAt, now: now)
    }

    private static func age(bornOn: Date, now: Date) -> Age? {
        let calendar = WeekCalendar.calendar
        let since = calendar.dateComponents([.year, .month, .day], from: bornOn, to: now)
        guard let years = since.year, let months = since.month, let days = since.day, years >= 0, months >= 0,
            days >= 0
        else { return nil }
        if years > 0 { return .years(years) }
        if months > 0 { return .months(months) }
        return .weeks(days / 7)
    }

    // MARK: Machine-readable lines

    /// The two lines at the bottom of the page, in the layout of the
    /// machine-readable zone of a passport: the name in the first line, and
    /// the number, the date of birth and the issue date in the second. A
    /// value that is not known stays filled with "<". The check digits stay
    /// empty, because nothing reads them.
    var machineReadableLines: [String] {
        let first = "P<CHE" + Self.letters(of: name)
        let number = String(id.uuidString.replacingOccurrences(of: "-", with: "").prefix(9))
        let second = number + "<CHE" + Self.field(bornOn) + String(repeating: "<", count: 9) + Self.field(issuedAt)
        return [first, second].map { $0.padding(toLength: Self.lineLength, withPad: "<", startingAt: 0) }
    }

    private static let lineLength = 44

    /// The name in capital letters without accents, with "<" for each other
    /// character.
    private static func letters(of name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_CH"))
        return String(folded.uppercased().map { ("A"..."Z").contains($0) ? $0 : "<" })
    }

    /// The day as YYMMDD, or "<<<<<<".
    private static func field(_ date: Date?) -> String {
        guard let date else { return String(repeating: "<", count: 6) }
        return String(WeekCalendar.dayText(of: date).replacingOccurrences(of: "-", with: "").dropFirst(2))
    }
}
