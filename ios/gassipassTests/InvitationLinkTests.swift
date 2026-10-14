//
//  InvitationLinkTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 14.10.2026.
//

import Foundation
import Testing
@testable import gassipass

/// The link of an invitation, which the share sheet sends and which opens
/// the app.
struct InvitationLinkTests {
    @Test func theLinkCarriesTheTokenOnGassipassCh() {
        let link = InvitationLink.url(token: "Ab3_-x")

        #expect(link.absoluteString == "https://gassipass.ch/invitation/Ab3_-x")
        #expect(InvitationLink.token(in: link) == "Ab3_-x")
    }

    @Test func aLinkWithATrailingSlashCarriesTheSameToken() {
        #expect(InvitationLink.token(in: URL(string: "https://gassipass.ch/invitation/Ab3_-x/")!) == "Ab3_-x")
    }

    @Test(arguments: [
        "https://gassipass.ch/",
        "https://gassipass.ch/invitation",
        "https://gassipass.ch/invitation/",
        "https://gassipass.ch/invitation/Ab3/more",
        "https://gassipass.ch/invitation/Ab%20c",
        "https://example.com/invitation/Ab3",
        "http://gassipass.ch/invitation/Ab3",
        "https://gassipass.ch/other/Ab3",
    ])
    func anotherLinkCarriesNoToken(link: String) {
        #expect(InvitationLink.token(in: URL(string: link)!) == nil)
    }
}
