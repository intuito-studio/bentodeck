import XCTest
import SwiftUI
@testable import BentoDeck

final class ThemeTests: XCTestCase {

    // MARK: - Color(hex:) parser

    func testColorHexRRGGBBParsesWithLeadingHash() {
        // Should not fall back to gray; we can't directly read a Color's
        // channel values on every platform, but we can at least assert
        // that two equivalent inputs produce equal Colors and that a
        // known-bad input produces a different Color.
        let c1 = Color(hex: "#FF7A1A")
        let c2 = Color(hex: "#ff7a1a")
        let fallback = Color.gray
        XCTAssertEqual(c1, c2, "Hex parsing must be case-insensitive")
        XCTAssertNotEqual(c1, fallback, "Valid hex should not fall back to gray")
    }

    func testColorHexRRGGBBParsesWithoutLeadingHash() {
        let withHash = Color(hex: "#27C26A")
        let noHash = Color(hex: "27C26A")
        XCTAssertEqual(withHash, noHash, "Leading # must be optional")
    }

    func testColorHexRRGGBBAAParses() {
        let opaqueAlpha = Color(hex: "#FF7A1AFF")
        let partialAlpha = Color(hex: "#FF7A1A55")
        let fallback = Color.gray
        XCTAssertNotEqual(opaqueAlpha, fallback, "Valid 8-digit hex should parse")
        XCTAssertNotEqual(partialAlpha, fallback, "Valid 8-digit hex with alpha should parse")
        XCTAssertNotEqual(opaqueAlpha, partialAlpha, "Different alpha should produce different colors")
    }

    func testColorHexEmptyStringFallsBackToGray() {
        XCTAssertEqual(Color(hex: ""), Color.gray)
    }

    func testColorHexGarbageFallsBackToGray() {
        XCTAssertEqual(Color(hex: "garbage"), Color.gray)
        XCTAssertEqual(Color(hex: "#ZZZZZZ"), Color.gray)
    }

    func testColorHexWrongLengthFallsBackToGray() {
        XCTAssertEqual(Color(hex: "#FFF"), Color.gray, "3-digit hex unsupported")
        XCTAssertEqual(Color(hex: "#FFFF"), Color.gray, "4-digit hex unsupported")
        XCTAssertEqual(Color(hex: "#FFFFFFF"), Color.gray, "7-digit hex unsupported")
        XCTAssertEqual(Color(hex: "#FFFFFFFFF"), Color.gray, "9-digit hex unsupported")
    }

    func testColorHexTrimsWhitespace() {
        let trimmed = Color(hex: "  #FF7A1A  ")
        let clean = Color(hex: "#FF7A1A")
        XCTAssertEqual(trimmed, clean, "Leading/trailing whitespace must be trimmed")
    }

    // MARK: - Theme Codable roundtrip

    func testThemeFallbackHasSensibleValues() {
        let t = Theme.fallback
        XCTAssertEqual(t.id, "default")
        XCTAssertEqual(t.name, "Default")
        XCTAssertFalse(t.colors.background.isEmpty)
        XCTAssertTrue(t.colors.background.hasPrefix("#"))
        XCTAssertTrue(t.colors.accent.hasPrefix("#"))
        XCTAssertEqual(t.font.weightPrimary, .bold)
        XCTAssertEqual(t.font.family, .default)
        XCTAssertFalse(t.chart.stroke.isEmpty)
    }

    func testThemeCodableRoundtrip() throws {
        let original = Theme.fallback
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Theme.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testThemeDecodesFromServerLikeJSON() throws {
        let json = """
        {
          "id": "sunset",
          "name": "Sunset",
          "colors": {
            "background": "#1a0b0b",
            "surface": "#2a1414",
            "primary": "#ffe5d0",
            "secondary": "#c89a8a",
            "accent": "#ff7a1a",
            "positive": "#27c26a",
            "negative": "#ff5252",
            "border": "#3a2222"
          },
          "font": { "family": "rounded", "weightPrimary": "heavy" },
          "chart": { "stroke": "#ff7a1a", "fillStart": "#ff7a1a55", "fillEnd": "#ff7a1a00" }
        }
        """.data(using: .utf8)!

        let t = try JSONDecoder().decode(Theme.self, from: json)
        XCTAssertEqual(t.id, "sunset")
        XCTAssertEqual(t.font.family, .rounded)
        XCTAssertEqual(t.font.weightPrimary, .heavy)
        XCTAssertEqual(t.chart.stroke, "#ff7a1a")
    }

    // MARK: - ThemeFont.Weight SwiftUI mapping

    func testThemeFontWeightMapsToSwiftUIWeight() {
        XCTAssertEqual(ThemeFont.Weight.regular.swift, Font.Weight.regular)
        XCTAssertEqual(ThemeFont.Weight.medium.swift, Font.Weight.medium)
        XCTAssertEqual(ThemeFont.Weight.semibold.swift, Font.Weight.semibold)
        XCTAssertEqual(ThemeFont.Weight.bold.swift, Font.Weight.bold)
        XCTAssertEqual(ThemeFont.Weight.heavy.swift, Font.Weight.heavy)
    }

    func testThemeFontWeightCodable() throws {
        for w in [ThemeFont.Weight.regular, .medium, .semibold, .bold, .heavy] {
            let data = try JSONEncoder().encode(w)
            let decoded = try JSONDecoder().decode(ThemeFont.Weight.self, from: data)
            XCTAssertEqual(w, decoded)
        }
    }

    func testThemeFontFamilyCodable() throws {
        for f in [ThemeFont.Family.rounded, .serif, .monospaced, .default] {
            let data = try JSONEncoder().encode(f)
            let decoded = try JSONDecoder().decode(ThemeFont.Family.self, from: data)
            XCTAssertEqual(f, decoded)
        }
    }
}
