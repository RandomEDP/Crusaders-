import XCTest
@testable import CrusadersKit

final class ThemePaletteTests: XCTestCase {
    private let minimum = ThemePalette.minimumTextContrast

    func testContrastRatioMatchesKnownValues() {
        let black = RGBColor(hex: 0x000000), white = RGBColor(hex: 0xFFFFFF)
        XCTAssertEqual(black.contrastRatio(with: white), 21, accuracy: 0.01)
        XCTAssertEqual(white.contrastRatio(with: white), 1, accuracy: 0.01)
        XCTAssertEqual(RGBColor(hex: 0x777777).contrastRatio(with: white), 4.48, accuracy: 0.01)
    }

    func testHexParsing() {
        XCTAssertEqual(RGBColor(hex: 0x8E1B1B), RGBColor(142, 27, 27))
    }

    func testBlending() {
        let mid = RGBColor(hex: 0x000000).blended(over: RGBColor(hex: 0xFFFFFF), opacity: 0.5)
        XCTAssertEqual(mid, RGBColor(127.5, 127.5, 127.5))
    }

    /// The card colour as it actually appears over the darkest part of the parchment.
    private var cardOverEdge: RGBColor {
        ThemePalette.card.blended(over: ThemePalette.parchmentEdge, opacity: ThemePalette.cardOpacity)
    }

    func testBodyTextIsEasyToReadOnEveryBackground() {
        // Main text aims for AAA (7:1) everywhere.
        for background in [ThemePalette.parchment, ThemePalette.parchmentEdge, ThemePalette.card, cardOverEdge] {
            XCTAssertGreaterThanOrEqual(ThemePalette.ink.contrastRatio(with: background), 7, "\(background)")
        }
    }

    func testSecondaryTextMeetsAA() {
        for background in [ThemePalette.parchment, ThemePalette.card, cardOverEdge] {
            XCTAssertGreaterThanOrEqual(ThemePalette.inkSoft.contrastRatio(with: background), minimum, "\(background)")
        }
    }

    func testAccentMeetsAA() {
        for background in [ThemePalette.parchment, ThemePalette.card, cardOverEdge] {
            XCTAssertGreaterThanOrEqual(ThemePalette.crimson.contrastRatio(with: background), minimum, "\(background)")
        }
    }

    func testWhiteTextOnCrimsonButtonsMeetsAA() {
        XCTAssertGreaterThanOrEqual(RGBColor(hex: 0xFFFFFF).contrastRatio(with: ThemePalette.crimson), minimum)
    }

    func testFontsAreDistinctAndHaveFiles() {
        let names = ThemeFont.allCases.map(\.rawValue)
        XCTAssertEqual(Set(names).count, names.count)
        for font in ThemeFont.allCases {
            XCTAssertTrue(font.fileName.hasSuffix(".ttf"), font.fileName)
        }
    }

    func testSerifIsSetLargerThanSystemSoItReadsTheSame() {
        XCTAssertEqual(ThemeFont.serif.pointSize(forTextStyle: "body"), 20)
        XCTAssertEqual(ThemeFont.gothic.pointSize(forTextStyle: "largeTitle"), 34)
        XCTAssertGreaterThanOrEqual(ThemeFont.serif.pointSize(forTextStyle: "caption2"), 12)
    }
}
