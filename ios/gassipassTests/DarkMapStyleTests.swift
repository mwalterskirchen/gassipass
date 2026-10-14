//
//  DarkMapStyleTests.swift
//  gassipassTests
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation
import Testing
@testable import gassipass

struct DarkMapStyleTests {
    @Test func lightLandBecomesDarkAndDarkLabelsBecomeLight() throws {
        let land = try components(DarkMapStyle.darkenedColor("rgba(252, 252, 252, 1)"))
        let label = try components(DarkMapStyle.darkenedColor("#333"))
        #expect(land.lightness < 0.2)
        #expect(label.lightness > 0.6)
    }

    @Test func coloursKeepTheirHue() throws {
        let water = try components(DarkMapStyle.darkenedColor("rgb(199, 224, 245)"))
        let forest = try components(DarkMapStyle.darkenedColor("hsl(100, 30%, 75%)"))
        #expect(water.blue > water.red)
        #expect(forest.green > forest.red && forest.green > forest.blue)
    }

    @Test func transparencyStays() throws {
        let colour = try #require(DarkMapStyle.darkenedColor("rgba(0, 0, 0, 0.25)"))
        #expect(colour.hasSuffix(", 0.25)"))
    }

    @Test func reliefShadowsStayDarkerThanTheLand() throws {
        let land = try components(DarkMapStyle.darkenedColor("rgba(252, 252, 252, 1)"))
        let shadow = try components(DarkMapStyle.darkenedColor("rgb(200,210,213)", isRelief: true))
        #expect(shadow.lightness < land.lightness)
    }

    @Test func textThatIsNoColourStays() {
        #expect(DarkMapStyle.darkenedColor("get") == nil)
        #expect(DarkMapStyle.darkenedColor("luminosity") == nil)
        #expect(DarkMapStyle.darkenedColor("#zzz") == nil)
    }

    @Test func styleChangesOnlyTheColoursOfThePaint() throws {
        let light = """
            {"version": 8, "sources": {}, "layers": [
              {"id": "water", "type": "fill", "layout": {"visibility": "#ffffff"},
               "paint": {"fill-color": ["match", ["get", "class"], "lake", "#ffffff", "rgb(0, 0, 0)"],
                         "fill-opacity": 0.5}}
            ]}
            """
        let dark = try DarkMapStyle.darkened(Data(light.utf8))
        let layer = try #require(
            (JSONSerialization.jsonObject(with: Data(dark.utf8)) as? [String: Any])?["layers"] as? [[String: Any]]
        ).first
        let paint = try #require(layer?["paint"] as? [String: Any])
        let fill = try #require(paint["fill-color"] as? [Any])
        #expect(fill[0] as? String == "match")
        #expect(fill[1] as? [String] == ["get", "class"])
        #expect(fill[2] as? String == "lake")
        #expect(try components(fill[3] as? String).lightness < 0.2)
        #expect(try components(fill[4] as? String).lightness > 0.8)
        #expect(paint["fill-opacity"] as? Double == 0.5)
        #expect((layer?["layout"] as? [String: String])?["visibility"] == "#ffffff")
    }

    /// The components of an `rgba()` colour from 0 to 1, and its lightness.
    private func components(_ text: String?) throws -> (red: Double, green: Double, blue: Double, lightness: Double) {
        let text = try #require(text)
        let numbers = text.dropFirst("rgba(".count).dropLast().split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        try #require(numbers.count == 4)
        let (red, green, blue) = (numbers[0] / 255, numbers[1] / 255, numbers[2] / 255)
        return (red, green, blue, (max(red, green, blue) + min(red, green, blue)) / 2)
    }
}
