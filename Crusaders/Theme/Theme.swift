import SwiftUI
import UIKit
import CrusadersKit

/// The app's old-parchment look. Colours live in `ThemePalette` (CrusadersKit) so their contrast is tested.
enum Theme {
    static let parchment = Color(ThemePalette.parchment)
    static let card = Color(ThemePalette.card).opacity(ThemePalette.cardOpacity)
    static let ink = Color(ThemePalette.ink)
    static let inkSoft = Color(ThemePalette.inkSoft)
    static let crimson = Color(ThemePalette.crimson)
    static let rule = Color(ThemePalette.rule)

    /// Styles UIKit-drawn parts SwiftUI can't reach: navigation bar titles and buttons, segmented controls.
    @MainActor
    static func applyAppearance() {
        let ink = UIColor(ThemePalette.ink)
        let crimson = UIColor(ThemePalette.crimson)

        let titleFont = UIFont.themed(.gothic, textStyle: .title3, size: 22)
        let largeTitleFont = UIFont.themed(.gothic, textStyle: .largeTitle, size: 36)
        let buttonFont = UIFont.themed(.serifBold, textStyle: .body, size: 19)

        let buttons = UIBarButtonItemAppearance()
        buttons.normal.titleTextAttributes = [.font: buttonFont, .foregroundColor: crimson]

        // Scrolled to the top: the parchment shows through. Scrolled: a solid strip of parchment.
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        let standard = UINavigationBarAppearance()
        standard.configureWithOpaqueBackground()
        standard.backgroundColor = UIColor(ThemePalette.parchment)
        standard.shadowColor = UIColor(ThemePalette.rule).withAlphaComponent(0.5)
        for appearance in [edge, standard] {
            appearance.titleTextAttributes = [.font: titleFont, .foregroundColor: ink]
            appearance.largeTitleTextAttributes = [.font: largeTitleFont, .foregroundColor: ink]
            appearance.buttonAppearance = buttons
            appearance.backButtonAppearance = buttons
        }
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = edge
        bar.tintColor = crimson

        let segments = UISegmentedControl.appearance()
        segments.selectedSegmentTintColor = UIColor(ThemePalette.card)
        segments.backgroundColor = UIColor(ThemePalette.parchmentEdge).withAlphaComponent(0.35)
        segments.setTitleTextAttributes([.font: UIFont.themed(.serif, textStyle: .subheadline, size: 17), .foregroundColor: ink], for: .normal)
        segments.setTitleTextAttributes([.font: UIFont.themed(.serifBold, textStyle: .subheadline, size: 17), .foregroundColor: ink], for: .selected)
    }
}

extension Color {
    init(_ rgb: ThemeColor) {
        self.init(.sRGB, red: rgb.red / 255, green: rgb.green / 255, blue: rgb.blue / 255, opacity: 1)
    }
}

extension UIColor {
    convenience init(_ rgb: ThemeColor) {
        self.init(red: rgb.red / 255, green: rgb.green / 255, blue: rgb.blue / 255, alpha: 1)
    }
}

extension UIFont {
    /// A bundled font that grows with the person's text size setting.
    static func themed(_ font: ThemeFont, textStyle: UIFont.TextStyle, size: CGFloat) -> UIFont {
        let base = UIFont(name: font.rawValue, size: size) ?? .preferredFont(forTextStyle: textStyle)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }
}

extension Font {
    /// Gothic blackletter, for titles and headings only.
    static func gothic(_ style: Font.TextStyle) -> Font { themed(.gothic, style) }
    /// Readable serif for body text.
    static func serif(_ style: Font.TextStyle) -> Font { themed(.serif, style) }
    static func serifBold(_ style: Font.TextStyle) -> Font { themed(.serifBold, style) }
    static func serifItalic(_ style: Font.TextStyle) -> Font { themed(.serifItalic, style) }

    private static func themed(_ font: ThemeFont, _ style: Font.TextStyle) -> Font {
        .custom(font.rawValue, size: font.pointSize(forTextStyle: style.name), relativeTo: style)
    }
}

private extension Font.TextStyle {
    var name: String {
        switch self {
        case .largeTitle: return "largeTitle"
        case .title: return "title"
        case .title2: return "title2"
        case .title3: return "title3"
        case .headline: return "headline"
        case .subheadline: return "subheadline"
        case .callout: return "callout"
        case .footnote: return "footnote"
        case .caption: return "caption"
        case .caption2: return "caption2"
        default: return "body"
        }
    }
}

/// Aged paper behind a whole screen.
struct ParchmentBackground: View {
    var body: some View {
        Theme.parchment
            .overlay {
                Image("Parchment")
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

extension View {
    /// Puts a screen (list, form or plain view) on parchment.
    func parchmentScreen() -> some View {
        scrollContentBackground(.hidden)
            .background { ParchmentBackground() }
    }

    /// App-wide defaults: serif ink text, crimson accents, always the light parchment look.
    func crusadersTheme() -> some View {
        font(.serif(.body))
            .foregroundStyle(Theme.ink)
            .tint(Theme.crimson)
            .preferredColorScheme(.light)
    }

    /// A row that isn't inside a `ThemedSection` still gets the paper card behind it.
    func parchmentRow() -> some View {
        listRowBackground(Theme.card)
    }
}

/// A list or form section with paper-card rows, a gothic heading and serif footer.
struct ThemedSection<Content: View, Header: View, Footer: View>: View {
    private let content: Content
    private let header: Header
    private let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        Section {
            content
        } header: {
            header
                .font(.gothic(.title3))
                .foregroundStyle(Theme.ink)
                .textCase(nil)
        } footer: {
            footer
                .font(.serif(.footnote))
                .foregroundStyle(Theme.inkSoft)
        }
        .listRowBackground(Theme.card)
    }
}

extension ThemedSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension ThemedSection where Header == Text, Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }
}

extension ThemedSection where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

extension ThemedSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}

extension Font {
    /// Big join-code digits, every digit the same width.
    static var joinCode: Font {
        .custom(ThemeFont.serifBold.rawValue, size: 48, relativeTo: .largeTitle).monospacedDigit()
    }
}

extension View {
    /// A light sheet of paper with a thin brown rule, in place of the system's grey material.
    func paperCard<S: InsettableShape>(_ shape: S) -> some View {
        background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.rule.opacity(0.6), lineWidth: 1))
    }
}
