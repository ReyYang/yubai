import Foundation
import XCTest
@testable import YubaiCore

final class SVGPathParserTests: XCTestCase {
    private struct DesignTokensDocument: Decodable {
        struct IconSection: Decodable {
            struct Glyph: Decodable {
                struct Stroke: Decodable { let d: String; let width: Double }
                let remix: String?
                let custom: String?
                let stroke: Stroke?
                let d: String
            }
            let grid: Double
            let glyphs: [String: Glyph]
        }
        let icon: IconSection
    }

    private func loadDesignTokens() throws -> DesignTokensDocument {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("design-tokens.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DesignTokensDocument.self, from: data)
    }

    func testAllDesignSystemGlyphsParseInside24Grid() throws {
        let tokens = try loadDesignTokens()
        XCTAssertEqual(tokens.icon.grid, 24)
        XCTAssertEqual(tokens.icon.glyphs.count, 90)

        for (name, glyph) in tokens.icon.glyphs {
            // Remix glyphs fill the 24 grid; custom 余白 glyphs share it and may add one stroked line.
            XCTAssertTrue((glyph.remix != nil) != (glyph.custom != nil), "\(name) needs exactly one source")
            if glyph.stroke != nil { XCTAssertNotNil(glyph.custom, "\(name) only custom glyphs stroke") }
            let grid = tokens.icon.grid
            let commands = try SVGPathParser.parse(glyph.d)
            XCTAssertFalse(commands.isEmpty, "Empty commands for \(name)")
            let bounds = try XCTUnwrap(SVGPathParser.boundingBox(of: commands), "Missing bounds for \(name)")
            XCTAssertGreaterThanOrEqual(bounds.minX, -0.05, "\(name) minX=\(bounds.minX)")
            XCTAssertGreaterThanOrEqual(bounds.minY, -0.05, "\(name) minY=\(bounds.minY)")
            XCTAssertLessThanOrEqual(bounds.maxX, grid + 0.05, "\(name) maxX=\(bounds.maxX)")
            XCTAssertLessThanOrEqual(bounds.maxY, grid + 0.05, "\(name) maxY=\(bounds.maxY)")
            XCTAssertGreaterThan(bounds.maxX - bounds.minX, 1, "\(name) degenerate width")
            XCTAssertGreaterThan(bounds.maxY - bounds.minY, 1, "\(name) degenerate height")
        }
    }

    func testKnownGlyphBoundsMatchWithinTolerance() throws {
        let tokens = try loadDesignTokens()

        let addGlyph = try XCTUnwrap(tokens.icon.glyphs["add"])
        let addBounds = try XCTUnwrap(SVGPathParser.boundingBox(of: try SVGPathParser.parse(addGlyph.d)))
        XCTAssertEqual(addBounds.minX, 5.0, accuracy: 0.05)
        XCTAssertEqual(addBounds.minY, 5.0, accuracy: 0.05)
        XCTAssertEqual(addBounds.maxX, 19.0, accuracy: 0.05)
        XCTAssertEqual(addBounds.maxY, 19.0, accuracy: 0.05)

        let foodGlyph = try XCTUnwrap(tokens.icon.glyphs["cat-food"])
        let foodBounds = try XCTUnwrap(SVGPathParser.boundingBox(of: try SVGPathParser.parse(foodGlyph.d)))
        XCTAssertEqual(foodBounds.minX, 2.0, accuracy: 0.1)
        XCTAssertEqual(foodBounds.minY, 0.5, accuracy: 0.1)
        XCTAssertEqual(foodBounds.maxX, 22.0, accuracy: 0.1)
        XCTAssertEqual(foodBounds.maxY, 21.0, accuracy: 0.1)
    }

    func testSupportsAllSVGCommandsAndCompressedArcFlags() throws {
        let path = "M10 10 L30 10 l10 10 H50 h10 V30 v10 C60 50 70 50 80 40 c10 -10 20 -10 30 0 S130 50 140 40 s10 -10 20 0 Q170 20 180 40 q10 20 20 0 T220 40 t20 0 A10 10 0 00240 60 a10 10 0 01-10 10 Z"
        let commands = try SVGPathParser.parse(path)
        let bounds = try XCTUnwrap(SVGPathParser.boundingBox(of: commands))
        XCTAssertGreaterThanOrEqual(bounds.minX, 10)
        XCTAssertLessThanOrEqual(bounds.maxX, 245)
        XCTAssertTrue(commands.contains(.close))
        XCTAssertTrue(commands.contains { if case .quadTo = $0 { return true }; return false })
        XCTAssertTrue(commands.contains { if case .cubicTo = $0 { return true }; return false })
    }
}
