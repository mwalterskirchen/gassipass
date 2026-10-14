//
//  DarkMapStyle.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 28.09.2026.
//

import Foundation

/// A dark version of a MapLibre style, for the map in dark mode. swisstopo
/// publishes no dark base map, so the app makes one from the light base map.
/// Every colour keeps its hue and gets the opposite lightness: light land
/// becomes dark land, and dark labels become light labels. Greys get a
/// slight blue tint, and yellow and orange lose most of their colour, so
/// that only collected segments are apricot.
///
/// The relief shading keeps its direction, so that shadows stay darker than
/// the land around them.
///
/// The app stores the dark style of the last download, so that the dark map
/// opens at once and also opens without a network.
nonisolated enum DarkMapStyle {
    /// The layers of the relief shading, by the start of their identifier.
    private static let reliefLayerPrefix = "hillshade"

    /// The dark style of the last download, or nil if there is none yet.
    static func stored() -> String? {
        try? String(contentsOf: storageURL, encoding: .utf8)
    }

    /// Downloads the style, makes it dark and stores it.
    static func download(from url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        let dark = try darkened(data)
        try? dark.write(to: storageURL, atomically: true, encoding: .utf8)
        return dark
    }

    /// The dark version of the style JSON. It changes only the colours in
    /// the paint properties of the layers.
    static func darkened(_ styleJSON: Data) throws -> String {
        guard var style = try JSONSerialization.jsonObject(with: styleJSON) as? [String: Any],
              let layers = style["layers"] as? [[String: Any]]
        else { throw CocoaError(.coderReadCorrupt) }
        style["layers"] = layers.map { layer in
            var layer = layer
            let isRelief = (layer["id"] as? String)?.hasPrefix(reliefLayerPrefix) ?? false
            if let paint = layer["paint"] {
                layer["paint"] = darkened(paint, isRelief: isRelief)
            }
            return layer
        }
        let data = try JSONSerialization.data(withJSONObject: style)
        return String(decoding: data, as: UTF8.self)
    }

    private static func darkened(_ value: Any, isRelief: Bool) -> Any {
        switch value {
        case let string as String:
            darkenedColor(string, isRelief: isRelief) ?? string
        case let array as [Any]:
            array.map { darkened($0, isRelief: isRelief) }
        case let dictionary as [String: Any]:
            dictionary.mapValues { darkened($0, isRelief: isRelief) }
        default:
            value
        }
    }

    /// The dark version of a colour of a style, or nil if the text is not a
    /// colour, for example the name of a property in an expression.
    static func darkenedColor(_ text: String, isRelief: Bool = false) -> String? {
        guard let color = RGBA(text) else { return nil }
        var (hue, saturation, lightness) = color.hsl
        if isRelief {
            // Darker shading on dark land, in the same direction as on light land.
            lightness *= 0.12
        } else {
            lightness = 0.1 + (1 - lightness) * 0.8
            if saturation < 0.08 {
                (hue, saturation) = (220, 0.1)
            } else if (20...70).contains(hue) {
                // Yellow and orange lines of the base map would look like collected segments.
                saturation *= 0.3
            } else {
                saturation *= 0.85
            }
        }
        return RGBA(hue: hue, saturation: saturation, lightness: lightness, alpha: color.alpha).text
    }

    /// Increase it when the colours change, so that the app does not show a
    /// stored style with the old colours.
    private static let version = 2

    private static var storageURL: URL {
        URL.cachesDirectory.appending(path: "DarkBaseMap-\(version).json")
    }
}

/// A colour of a MapLibre style, with components from 0 to 1.
nonisolated private struct RGBA {
    var red: Double, green: Double, blue: Double, alpha: Double

    /// Reads the colour formats of the swisstopo styles: `#rgb`, `#rrggbb`,
    /// `rgb()`, `rgba()`, `hsl()` and `hsla()`.
    init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") {
            var hex = String(text.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
            let shift = hex.count == 8 ? 8 : 0
            self.init(
                red: Double((value >> (16 + shift)) & 0xFF) / 255,
                green: Double((value >> (8 + shift)) & 0xFF) / 255,
                blue: Double((value >> shift) & 0xFF) / 255,
                alpha: hex.count == 8 ? Double(value & 0xFF) / 255 : 1)
            return
        }
        guard let open = text.firstIndex(of: "("), text.hasSuffix(")") else { return nil }
        let function = text[..<open]
        let numbers = text[text.index(after: open)..<text.index(before: text.endIndex)]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "") }
            .compactMap(Double.init)
        let alpha = numbers.count == 4 ? numbers[3] : 1
        switch (function, numbers.count) {
        case ("rgb", 3), ("rgba", 4):
            self.init(red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255, alpha: alpha)
        case ("hsl", 3), ("hsla", 4):
            self.init(hue: numbers[0], saturation: numbers[1] / 100, lightness: numbers[2] / 100, alpha: alpha)
        default:
            return nil
        }
    }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
    }

    init(hue: Double, saturation: Double, lightness: Double, alpha: Double) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch sector {
        case ..<1: (chroma, x, 0)
        case ..<2: (x, chroma, 0)
        case ..<3: (0, chroma, x)
        case ..<4: (0, x, chroma)
        case ..<5: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        let m = lightness - chroma / 2
        self.init(red: r + m, green: g + m, blue: b + m, alpha: alpha)
    }

    /// The hue in degrees, and the saturation and the lightness from 0 to 1.
    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maximum = max(red, green, blue), minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        let delta = maximum - minimum
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        let hue: Double = switch maximum {
        case red: 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: 60 * ((blue - red) / delta + 2)
        default: 60 * ((red - green) / delta + 4)
        }
        return ((hue + 360).truncatingRemainder(dividingBy: 360), saturation, lightness)
    }

    var text: String {
        func byte(_ component: Double) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return "rgba(\(byte(red)), \(byte(green)), \(byte(blue)), \(alpha))"
    }
}
