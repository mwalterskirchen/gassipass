//
//  IdentityPage.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 25.10.2026.
//

import SwiftUI

/// The first page of the passport, like the data page of a real passport:
/// the photo of the dog, its name, its date of birth with its age, the
/// retirement date of a retired dog, and the issue date. The two
/// machine-readable lines at the bottom repeat them.
///
/// A dog with an unknown date of birth shows no date of birth.
struct IdentityPage: View {
    let identity: PassportIdentity
    let photo: Data?

    @ScaledMetric(relativeTo: .title2) private var photoWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                portrait
                    .frame(width: photoWidth, height: photoWidth * 4 / 3)
                    .clipShape(.rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 10) {
                    field("Name") {
                        Text(identity.name)
                            .font(.title2.bold())
                    }
                    if let bornOn = identity.bornOn {
                        field("Date of Birth") {
                            day(bornOn)
                            if let age = identity.age {
                                Text(Self.text(of: age))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let retiredOn = identity.retiredOn {
                        field("Retired") { day(retiredOn) }
                    }
                    if let issuedOn = identity.issuedOn {
                        field("Issue Date") { day(issuedOn) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            machineReadableLines
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var portrait: some View {
        if let image = photo.flatMap(UIImage.init(data:)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            Text(identity.name.prefix(1).uppercased())
                .font(.system(size: photoWidth * 0.5, weight: .bold).width(.condensed))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.collected)
                .accessibilityHidden(true)
        }
    }

    /// The lines of the machine-readable zone, in a monospaced face like
    /// OCR-B. They shrink to the width of the page and repeat only what the
    /// fields say, so VoiceOver skips them.
    private var machineReadableLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(identity.machineReadableLines, id: \.self) { line in
                Text(verbatim: line)
            }
        }
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func field(_ label: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            value()
        }
    }

    /// A day in Zurich, where the server keeps the date of birth.
    private func day(_ date: Date) -> some View {
        Text(date, format: Self.dayFormat)
            .font(.figures(.title3))
            .monospacedDigit()
    }

    private static let dayFormat: Date.FormatStyle = {
        var format = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits).year()
        format.timeZone = WeekCalendar.calendar.timeZone
        return format
    }()

    private static func text(of age: PassportIdentity.Age) -> String {
        switch age {
        case .years(let years): String(localized: "\(years) years old")
        case .months(let months): String(localized: "\(months) months old")
        case .weeks(let weeks): String(localized: "\(weeks) weeks old")
        }
    }
}

#Preview {
    List {
        IdentityPage(
            identity: PassportIdentity(
                id: UUID(), name: "Bello", bornOn: WeekCalendar.date(ofDayText: "2019-05-17"), retiredAt: nil,
                addedAt: .now, now: .now),
            photo: nil)
        IdentityPage(
            identity: PassportIdentity(
                id: UUID(), name: "Rex", bornOn: WeekCalendar.date(ofDayText: "2011-02-03"),
                retiredAt: WeekCalendar.date(ofDayText: "2025-06-14"), addedAt: .now, now: .now),
            photo: nil)
    }
}
