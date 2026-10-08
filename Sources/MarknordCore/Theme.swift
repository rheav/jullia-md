import AppKit

/// A colour kept as plain numbers, so themes can live in `static let`s under strict concurrency.
public struct RGBA: Hashable, Sendable {
    public var red: Double, green: Double, blue: Double, alpha: Double

    public init(_ hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    public func alpha(_ value: Double) -> RGBA {
        var copy = self
        copy.alpha = value
        return copy
    }

    public var ns: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// The six marker colours, the same set Copy Hub uses.
public enum MarkColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case yellow, green, blue, pink, purple, orange

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .yellow: "Amarelo"
        case .green: "Verde"
        case .blue: "Azul"
        case .pink: "Rosa"
        case .purple: "Roxo"
        case .orange: "Laranja"
        }
    }
}

public enum ThemeID: String, CaseIterable, Codable, Sendable, Identifiable {
    case polar, ink, snow, paper

    public var id: String { rawValue }
    public var theme: Theme { Theme.all[self]! }
}

/// How one marker colour looks in a theme: `fill` behind highlighted text, `stroke` for the comment underline and swatches.
public struct MarkTone: Sendable, Hashable {
    public var fill: RGBA
    public var stroke: RGBA
}

public struct Theme: Sendable, Identifiable {
    public var id: ThemeID
    public var name: String
    public var isDark: Bool
    /// Body text in New York instead of SF Pro.
    public var serif: Bool

    public var background: RGBA
    /// Sidebars and inspector.
    public var surface: RGBA
    public var text: RGBA
    public var secondaryText: RGBA
    public var heading: RGBA
    public var link: RGBA
    public var accent: RGBA
    public var codeBackground: RGBA
    public var codeText: RGBA
    public var quoteBar: RGBA
    public var quoteText: RGBA
    public var rule: RGBA
    public var selection: RGBA
    public var marks: [MarkColor: MarkTone]

    public func tone(_ color: MarkColor) -> MarkTone { marks[color]! }

    static func marks(fills: [UInt32], fillAlpha: Double, strokes: [UInt32]? = nil) -> [MarkColor: MarkTone] {
        var result: [MarkColor: MarkTone] = [:]
        for (index, color) in MarkColor.allCases.enumerated() {
            result[color] = MarkTone(
                fill: RGBA(fills[index], alpha: fillAlpha),
                stroke: RGBA((strokes ?? fills)[index])
            )
        }
        return result
    }

    public static let polar = Theme(
        id: .polar, name: "Polar", isDark: true, serif: false,
        background: RGBA(0x2A2F3C), surface: RGBA(0x323848),
        text: RGBA(0xD8DEE9), secondaryText: RGBA(0xAEB9CD), heading: RGBA(0xECEFF4),
        link: RGBA(0x8ECAE6), accent: RGBA(0x8ECAE6),
        codeBackground: RGBA(0x363D4E), codeText: RGBA(0xB2DBA4),
        quoteBar: RGBA(0x8ECAE6), quoteText: RGBA(0xAEB9CD),
        rule: RGBA(0xD9E0EE, alpha: 0.16), selection: RGBA(0x8ECAE6, alpha: 0.32),
        marks: marks(fills: [0xF2CF94, 0xB2DBA4, 0x8ECAE6, 0xE79AA4, 0xCBAAD9, 0xF2B48A], fillAlpha: 0.30)
    )

    public static let ink = Theme(
        id: .ink, name: "Ink", isDark: true, serif: true,
        background: RGBA(0x121214), surface: RGBA(0x1B1B1E),
        text: RGBA(0xE6E1D6), secondaryText: RGBA(0xA39C8F), heading: RGBA(0xF2E9D8),
        link: RGBA(0xF2B48A), accent: RGBA(0xF2B48A),
        codeBackground: RGBA(0x211F1D), codeText: RGBA(0xD8C7A4),
        quoteBar: RGBA(0xF2B48A), quoteText: RGBA(0xA39C8F),
        rule: RGBA(0xE6E1D6, alpha: 0.13), selection: RGBA(0xF2B48A, alpha: 0.28),
        marks: marks(fills: [0xE8C872, 0x9CC78F, 0x86B4D4, 0xE39AA0, 0xBFA2D6, 0xF2B48A], fillAlpha: 0.28)
    )

    public static let snow = Theme(
        id: .snow, name: "Snow", isDark: false, serif: false,
        background: RGBA(0xF1F4FA), surface: RGBA(0xE6ECF6),
        text: RGBA(0x2B3240), secondaryText: RGBA(0x55627D), heading: RGBA(0x3D4A68),
        link: RGBA(0x3F7FBF), accent: RGBA(0x3F7FBF),
        codeBackground: RGBA(0xE3E9F4), codeText: RGBA(0x3E6E4C),
        quoteBar: RGBA(0x3F7FBF), quoteText: RGBA(0x55627D),
        rule: RGBA(0x3D4A68, alpha: 0.15), selection: RGBA(0x3F7FBF, alpha: 0.22),
        marks: marks(
            fills: [0xF2CF94, 0xB2DBA4, 0xA9CFEE, 0xF0B3BB, 0xD6BFE2, 0xF6C6A4], fillAlpha: 0.62,
            strokes: [0xB3771C, 0x4F8F5F, 0x3F7FBF, 0xC2515F, 0x8A5FA8, 0xC46A2B]
        )
    )

    public static let paper = Theme(
        id: .paper, name: "Paper", isDark: false, serif: true,
        background: RGBA(0xF6F1E7), surface: RGBA(0xEDE5D5),
        text: RGBA(0x3B342B), secondaryText: RGBA(0x6E6355), heading: RGBA(0x2E2820),
        link: RGBA(0xA0522D), accent: RGBA(0xA0522D),
        codeBackground: RGBA(0xECE4D4), codeText: RGBA(0x7A5A2E),
        quoteBar: RGBA(0xA0522D), quoteText: RGBA(0x6E6355),
        rule: RGBA(0x3B342B, alpha: 0.15), selection: RGBA(0xA0522D, alpha: 0.20),
        marks: marks(
            fills: [0xECC96A, 0xA8C99A, 0x9FBFD9, 0xE3A5A5, 0xC4ABD6, 0xE9B48A], fillAlpha: 0.48,
            strokes: [0xB8862B, 0x5F8A4F, 0x4F7FA8, 0xB25555, 0x82609E, 0xB86A32]
        )
    )

    public static let all: [ThemeID: Theme] = [.polar: polar, .ink: ink, .snow: snow, .paper: paper]
}
