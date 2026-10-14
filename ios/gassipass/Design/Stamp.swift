//
//  Stamp.swift
//  gassipass
//
//  Created by Maximilian Walterskirchen on 29.09.2026.
//

import CoreLocation
import SwiftUI

/// A round stamp in forest ink, like the stamps of a hiking passport, for a
/// completed area or street. The name runs along the top of the ring and
/// the dogs along the bottom. The middle holds a picture and the date.
///
/// The ink has small gaps, and the stamp sits at a slight angle. Both come
/// from the name, so that a stamp looks the same every time.
struct Stamp<Picture: View>: View {
    let name: String
    let dogNames: [String]
    let date: Date
    /// The diameter, in points.
    var size: CGFloat = 160
    @ViewBuilder let picture: Picture

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(lineWidth: size * 0.035)
            Circle()
                .strokeBorder(lineWidth: size * 0.01)
                .padding(size * 0.14)
            // The letters sit halfway between the outer and the inner ring.
            ArcText(text: name.uppercased(), side: .top, radius: size * 0.41, fontSize: size * 0.085)
            ArcText(text: dogLine, side: .bottom, radius: size * 0.41, fontSize: size * 0.07)
            // Two dots part the name from the dogs, like on a postmark.
            HStack {
                Circle().frame(width: size * 0.035)
                Spacer()
                Circle().frame(width: size * 0.035)
            }
            .padding(.horizontal, size * 0.075)
            VStack(spacing: size * 0.02) {
                picture
                    .frame(width: size * 0.4, height: size * 0.3)
                Text(date, format: .dateTime.day(.twoDigits).month(.twoDigits).year())
                    .font(.system(size: size * 0.08, weight: .bold).width(.condensed))
                    .monospacedDigit()
            }
            .offset(y: size * 0.02)
        }
        .frame(width: size, height: size)
        .foregroundStyle(Color.stampInk)
        .mask(InkGaps(seed: seed, dotSize: max(size * 0.012, 1)))
        .rotationEffect(.degrees(Double(seed % 5) - 6))
        .accessibilityElement()
        .accessibilityLabel(Text("\(name), completed on \(date.formatted(date: .long, time: .omitted))"))
    }

    private var dogLine: String {
        dogNames.formatted(.list(type: .and)).uppercased()
    }

    private var seed: Int {
        name.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    }
}

extension Stamp where Picture == AreaOutline {
    /// The stamp of a completed area, with the outline of the area.
    init(area: Area.ID, name: String, dogNames: [String], date: Date, size: CGFloat = 160) {
        self.init(name: name, dogNames: dogNames, date: date, size: size) {
            AreaOutline(area: area)
        }
    }
}

/// A small square stamp with the date, for a completed area or street in a
/// list.
struct DateStamp: View {
    let date: Date

    var body: some View {
        Text(date, format: .dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits))
            .font(.figures(.subheadline, weight: .bold))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(lineWidth: 1.5)
            }
            .foregroundStyle(Color.stampInk)
            .mask(InkGaps(seed: Int(date.timeIntervalSinceReferenceDate / 86_400), dotSize: 1))
            .rotationEffect(.degrees(-3))
            .accessibilityElement()
            .accessibilityLabel(Text("Completed on \(date.formatted(date: .long, time: .omitted))"))
    }
}

/// Text that runs along a circle, upright at the top or at the bottom. It
/// shrinks to fit when it is longer than the arc.
private struct ArcText: View {
    enum Side {
        case top, bottom
    }

    let text: String
    let side: Side
    /// The distance from the centre to the middle of the letters.
    let radius: CGFloat
    let fontSize: CGFloat

    var body: some View {
        Canvas { context, size in
            let glyphs = text.map {
                context.resolve(Text(String($0)).font(.system(size: fontSize, weight: .heavy).width(.condensed)))
            }
            let widths = glyphs.map { $0.measure(in: size).width }
            let spacing = fontSize * 0.14
            let length = widths.reduce(0, +) + spacing * Double(max(glyphs.count - 1, 0))
            // The text takes at most a little less than half of the circle.
            let scale = min(1, radius * .pi * 0.72 / length)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            var position = -length * scale / 2
            for (glyph, width) in zip(glyphs, widths) {
                let angle = (position + width * scale / 2) / radius
                var glyphContext = context
                glyphContext.translateBy(x: center.x, y: center.y)
                switch side {
                case .top:
                    glyphContext.rotate(by: .radians(angle))
                    glyphContext.translateBy(x: 0, y: -radius)
                case .bottom:
                    glyphContext.rotate(by: .radians(-angle))
                    glyphContext.translateBy(x: 0, y: radius)
                }
                glyphContext.scaleBy(x: scale, y: scale)
                glyphContext.draw(glyph, at: .zero, anchor: .center)
                position += (width + spacing) * scale
            }
        }
        .accessibilityHidden(true)
    }
}

/// A mask that leaves small gaps in the ink, at places that come from the
/// seed.
private struct InkGaps: View {
    let seed: Int
    let dotSize: CGFloat

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            context.blendMode = .clear
            var random = SeededRandom(seed: UInt64(truncatingIfNeeded: seed))
            let count = Int(size.width * size.height / (dotSize * dotSize * 60))
            for _ in 0..<count {
                let x = random.next() * size.width, y = random.next() * size.height
                let d = dotSize * (0.5 + random.next())
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(.black))
            }
        }
    }
}

/// A small random number generator that gives the same numbers for the
/// same seed.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    /// A number from 0 to 1.
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}

/// The filled outline of an area, from the boundary in the map package.
struct AreaOutline: View {
    /// The BFS number of the area.
    let area: Area.ID
    @State private var boundary: [[CLLocationCoordinate2D]] = []

    var body: some View {
        Canvas { context, size in
            guard !boundary.isEmpty else { return }
            let project = AreaMapRenderer.projection(
                of: boundary.flatMap { $0 }, into: CGRect(origin: .zero, size: size))
            var path = Path()
            for ring in boundary {
                path.addLines(ring.map(project))
                path.closeSubpath()
            }
            context.fill(path, with: .foreground, style: FillStyle(eoFill: true))
        }
        .task(id: area) {
            boundary = await Self.boundary(of: area)
        }
        .accessibilityHidden(true)
    }

    @concurrent nonisolated private static func boundary(of area: Area.ID) async -> [[CLLocationCoordinate2D]] {
        ((try? MapPackages.bundled.boundary(of: area)) ?? nil) ?? []
    }
}

#Preview {
    VStack(spacing: 40) {
        Stamp(area: 87, name: "Hüttikon", dogNames: ["Bello"], date: .now)
        Stamp(name: "Oberdorfstrasse", dogNames: ["Bello", "Luna"], date: .now, size: 120) {
            Image(systemName: "pawprint.fill")
                .resizable()
                .scaledToFit()
        }
        DateStamp(date: .now)
    }
}
