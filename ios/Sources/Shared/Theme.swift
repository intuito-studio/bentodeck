import SwiftUI

/// Mirrors the server-side Theme JSON. Kept intentionally permissive so the
/// iOS side never crashes on an AI-generated theme that added or omitted
/// a field — any missing slot falls back to the default theme's value.
struct Theme: Codable, Hashable {
    let id: String
    let name: String
    let colors: ThemeColors
    let font: ThemeFont
    let chart: ThemeChart

    static let fallback = Theme(
        id: "default",
        name: "Default",
        colors: ThemeColors(
            background: "#0B0B0F",
            surface: "#17171D",
            primary: "#F5F5F7",
            secondary: "#9A9AA5",
            accent: "#FF7A1A",
            positive: "#27C26A",
            negative: "#FF5252",
            border: "#2A2A33"
        ),
        font: ThemeFont(family: .default, weightPrimary: .bold),
        chart: ThemeChart(stroke: "#FF7A1A", fillStart: "#FF7A1A55", fillEnd: "#FF7A1A00")
    )
}

struct ThemeColors: Codable, Hashable {
    let background: String
    let surface: String
    let primary: String
    let secondary: String
    let accent: String
    let positive: String
    let negative: String
    let border: String
}

struct ThemeFont: Codable, Hashable {
    enum Family: String, Codable { case rounded, serif, monospaced, `default` }
    enum Weight: String, Codable {
        case regular, medium, semibold, bold, heavy
        var swift: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            }
        }
    }
    let family: Family
    let weightPrimary: Weight
}

struct ThemeChart: Codable, Hashable {
    let stroke: String
    let fillStart: String
    let fillEnd: String
}

// MARK: - Color helpers

extension Color {
    /// Parses "#RRGGBB" or "#RRGGBBAA". Returns `.gray` on any parse failure —
    /// themes are inspected by humans, bad hex strings will show up immediately.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&rgb) else {
            self = .gray; return
        }
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((rgb & 0xFF0000) >> 16) / 255
            g = Double((rgb & 0x00FF00) >> 8) / 255
            b = Double(rgb & 0x0000FF) / 255
            a = 1
        case 8:
            r = Double((rgb & 0xFF000000) >> 24) / 255
            g = Double((rgb & 0x00FF0000) >> 16) / 255
            b = Double((rgb & 0x0000FF00) >> 8) / 255
            a = Double(rgb & 0x000000FF) / 255
        default:
            self = .gray; return
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Theme-driven fonts

extension Theme {
    func primaryFont(size: CGFloat) -> Font {
        let weight = font.weightPrimary.swift
        switch font.family {
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .monospaced: return .system(size: size, weight: weight, design: .monospaced)
        case .default: return .system(size: size, weight: weight, design: .default)
        }
    }

    func secondaryFont(size: CGFloat) -> Font {
        switch font.family {
        case .rounded: return .system(size: size, weight: .medium, design: .rounded)
        case .serif: return .system(size: size, weight: .medium, design: .serif)
        case .monospaced: return .system(size: size, weight: .medium, design: .monospaced)
        case .default: return .system(size: size, weight: .medium, design: .default)
        }
    }
}
