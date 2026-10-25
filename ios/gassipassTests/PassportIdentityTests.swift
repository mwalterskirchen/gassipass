//
//  PassportIdentityTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 25.10.2026.
//

import Foundation
import Testing
@testable import gassipass

/// The identity page of the passport: the age of a dog, the dates of a
/// retired dog, and the machine-readable lines.
struct PassportIdentityTests {
    let now = day("2026-10-25")

    @Test func aDogThatTakesPartInWalksShowsItsAgeInYearsFromItsFirstBirthday() {
        #expect(identity(bornOn: day("2019-05-17")).age == .years(7))
        #expect(identity(bornOn: day("2019-10-26")).age == .years(6))
        #expect(identity(bornOn: day("2025-10-25")).age == .years(1))
    }

    @Test func aYoungDogShowsItsAgeInMonthsOrInWeeks() {
        #expect(identity(bornOn: day("2025-10-26")).age == .months(11))
        #expect(identity(bornOn: day("2026-08-01")).age == .months(2))
        #expect(identity(bornOn: day("2026-10-10")).age == .weeks(2))
        #expect(identity(bornOn: day("2026-10-25")).age == .weeks(0))
    }

    @Test func aRetiredDogShowsItsDateOfBirthAndItsRetirementDateAndNoAge() {
        let retired = identity(bornOn: day("2012-03-01"), retiredAt: day("2025-06-14"))

        #expect(retired.bornOn == day("2012-03-01"))
        #expect(retired.retiredAt == day("2025-06-14"))
        #expect(retired.age == nil)
    }

    @Test func aDogWithoutADateOfBirthHasNoAge() {
        let unknown = identity(bornOn: nil)

        #expect(unknown.bornOn == nil)
        #expect(unknown.age == nil)
    }

    @Test func theMachineReadableLinesHoldTheNameTheDateOfBirthAndTheIssueDate() {
        let lines = PassportIdentity(
            id: UUID(uuidString: "4B1E2C3D-0000-0000-0000-000000000000")!, name: "Mäx vom Bach",
            bornOn: day("2019-05-17"), retiredAt: nil, addedAt: day("2026-03-12"), now: now
        ).machineReadableLines

        #expect(lines == [
            "P<CHEMAX<VOM<BACH<<<<<<<<<<<<<<<<<<<<<<<<<<<",
            "4B1E2C3D0<CHE190517<<<<<<<<<260312<<<<<<<<<<",
        ])
    }

    @Test func theMachineReadableLinesLeaveAnUnknownDateOfBirthEmpty() {
        let lines = PassportIdentity(
            id: UUID(uuidString: "4B1E2C3D-0000-0000-0000-000000000000")!, name: "Bello", bornOn: nil,
            retiredAt: nil, addedAt: day("2026-03-12"), now: now
        ).machineReadableLines

        #expect(lines[1] == "4B1E2C3D0<CHE<<<<<<<<<<<<<<<260312<<<<<<<<<<")
    }

    private func identity(bornOn: Date?, retiredAt: Date? = nil) -> PassportIdentity {
        PassportIdentity(
            id: UUID(), name: "Bello", bornOn: bornOn, retiredAt: retiredAt, addedAt: day("2026-03-12"), now: now)
    }
}

private func day(_ text: String) -> Date {
    WeekCalendar.date(ofDayText: text)!
}
