import XCTest
import UIKit
import CrusadersKit
@testable import Crusaders

/// The parchment look: bundled fonts load, the artwork is in the app, and colours stay readable.
final class ThemeTests: XCTestCase {
    func testEveryBundledFontIsRegistered() {
        for font in ThemeFont.allCases {
            XCTAssertNotNil(UIFont(name: font.rawValue, size: 17), "\(font.rawValue) did not load; check UIAppFonts in project.yml")
        }
    }

    func testFontLicencesShipWithTheApp() {
        for licence in ["OFL-GrenzeGotisch", "OFL-EBGaramond"] {
            XCTAssertNotNil(Bundle.main.url(forResource: licence, withExtension: "txt"), licence)
        }
    }

    func testThemedFontsUseTheBundledFaceAndScaleWithTextSize() {
        let font = UIFont.themed(.serif, textStyle: .body, size: 20)
        XCTAssertEqual(font.fontName, ThemeFont.serif.rawValue)
        let metrics = UIFontMetrics(forTextStyle: .body)
        let huge = metrics.scaledValue(for: 20, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge))
        let tiny = metrics.scaledValue(for: 20, compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraSmall))
        XCTAssertGreaterThan(huge, tiny)
    }

    func testLogoAndParchmentArtworkAreInTheApp() throws {
        let logo = try XCTUnwrap(UIImage(named: "Logo"))
        XCTAssertEqual(logo.size.width, logo.size.height, "logo should be square")
        let parchment = try XCTUnwrap(UIImage(named: "Parchment"))
        XCTAssertGreaterThan(parchment.size.height, parchment.size.width, "parchment is a portrait page")
    }

    func testAppAlwaysUsesTheLightParchmentLook() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle") as? String, "Light")
    }

    @MainActor
    func testNavigationBarUsesGothicTitlesAndInk() throws {
        Theme.applyAppearance()
        let appearance = UINavigationBar.appearance().standardAppearance
        let font = try XCTUnwrap(appearance.titleTextAttributes[.font] as? UIFont)
        XCTAssertEqual(font.fontName, ThemeFont.gothic.rawValue)
        let large = try XCTUnwrap(appearance.largeTitleTextAttributes[.font] as? UIFont)
        XCTAssertEqual(large.fontName, ThemeFont.gothic.rawValue)
        let colour = try XCTUnwrap(appearance.titleTextAttributes[.foregroundColor] as? UIColor)
        XCTAssertEqual(colour, UIColor(ThemePalette.ink))
    }
}
