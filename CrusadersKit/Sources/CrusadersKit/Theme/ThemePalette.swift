import Foundation

/// An sRGB colour with 0...255 channels, so the app's theme colours can be checked without UIKit.
public struct RGBColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
    }

    /// WCAG 2 relative luminance, 0 (black) to 1 (white).
    public var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            let c = value / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG 2 contrast ratio between two colours, from 1 to 21.
    public func contrastRatio(with other: RGBColor) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// This colour laid over `background` at the given opacity.
    public func blended(over background: RGBColor, opacity: Double) -> RGBColor {
        RGBColor(
            red * opacity + background.red * (1 - opacity),
            green * opacity + background.green * (1 - opacity),
            blue * opacity + background.blue * (1 - opacity)
        )
    }
}

/// The old-parchment look: dark ink on aged paper with crimson accents taken from the logo.
public enum ThemePalette {
    /// Main page colour, matching the middle of the parchment texture.
    public static let parchment = RGBColor(hex: 0xEBDDBE)
    /// The darkest, browned edge of the parchment texture.
    public static let parchmentEdge = RGBColor(hex: 0xC4A06C)
    /// Cards and list rows sit on a lighter sheet of paper.
    public static let card = RGBColor(hex: 0xF6EDD8)
    /// Opacity of the card colour over the texture.
    public static let cardOpacity = 0.88
    /// Main text.
    public static let ink = RGBColor(hex: 0x22140A)
    /// Secondary text (captions, subtitles).
    public static let inkSoft = RGBColor(hex: 0x5A4230)
    /// Accent for buttons, icons and links, the red of the shield's cross.
    public static let crimson = RGBColor(hex: 0x8E1B1B)
    /// Thin borders around cards.
    public static let rule = RGBColor(hex: 0x9C7A4E)

    /// WCAG AA for normal text.
    public static let minimumTextContrast = 4.5
}

/// Bundled typefaces. Both are SIL Open Font License 1.1 (see Crusaders/Resources/Fonts).
public enum ThemeFont: String, CaseIterable, Sendable {
    /// Gothic blackletter for titles and headings only.
    case gothic = "GrenzeGotisch-SemiBold"
    /// Readable old-style serif for everything else.
    case serif = "EBGaramond-Regular"
    case serifBold = "EBGaramond-SemiBold"
    case serifItalic = "EBGaramondItalic-Italic"

    /// The font file bundled with the app.
    public var fileName: String {
        switch self {
        case .gothic: return "GrenzeGotisch-SemiBold.ttf"
        case .serif: return "EBGaramond-Regular.ttf"
        case .serifBold: return "EBGaramond-SemiBold.ttf"
        case .serifItalic: return "EBGaramond-Italic.ttf"
        }
    }

    /// EB Garamond is small on the body for its point size, so it is set a little larger than the
    /// system font to read the same. Sizes match Apple's defaults at the Large text setting.
    public func pointSize(forTextStyle style: String) -> Double {
        let base: Double
        switch style {
        case "largeTitle": base = 34
        case "title": base = 28
        case "title2": base = 22
        case "title3": base = 20
        case "headline", "body": base = 17
        case "callout": base = 16
        case "subheadline": base = 15
        case "footnote": base = 13
        case "caption": base = 12
        case "caption2": base = 11
        default: base = 17
        }
        return self == .gothic ? base : (base * 1.15).rounded()
    }
}
