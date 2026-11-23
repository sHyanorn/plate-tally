import SwiftUI
import UIKit

/// The colours of the design (D017), each with a light and a dark value. The system picks the value from the
/// traits of the view, so a colour scheme that a test sets reaches it too. Moss is the only colour: it marks
/// the tag of a screen, and everything else is neutral.
enum Palette {
    static var canvas: Color { Color(light: 0xF4F1EA, dark: 0x0F0E0D) }
    static var surface: Color { Color(light: 0xFFFFFF, dark: 0x1D1B19) }
    static var surface2: Color { Color(light: 0xE9E5DC, dark: 0x2B2825) }
    static var ink: Color { Color(light: 0x14110F, dark: 0xF7F4EE) }
    static var ink2: Color { Color(light: 0x5E584F, dark: 0xB0AAA0) }
    /// The text on a primary button, whose fill is ink.
    static var onInk: Color { Color(light: 0xFFFFFF, dark: 0x14110F) }
    static var moss: Color { Color(light: 0x2F4F3E, dark: 0x44705A) }
    static var onMoss: Color { Color(light: 0xF4F1EA, dark: 0xF7F4EE) }
    /// Outlines and hairlines: ink at 14% in light, 16% in dark.
    static var line: Color { Color(light: 0x14110F, dark: 0xF7F4EE, lightAlpha: 0.14, darkAlpha: 0.16) }
}

/// Sizes of the layout in points.
enum Metrics {
    static let margin: CGFloat = 20
    static let gap: CGFloat = 12
    static let cardRadius: CGFloat = 28
    static let tagRadius: CGFloat = 32
    static let tagHeight: CGFloat = 132
    static let pillHeight: CGFloat = 58
}

/// The text of the design: the rounded system font at a fixed size that grows and shrinks with Dynamic Type
/// as the text style it follows does.
enum TextRole {
    case pageTitle
    case tagNumber
    case sideNumber
    case cardNumber
    case name
    case label
    case button
    case caption
    case unit

    var size: CGFloat {
        switch self {
        case .pageTitle: 40
        case .tagNumber: 58
        case .sideNumber: 28
        case .cardNumber: 24
        case .name: 17
        case .label: 15
        case .button: 18
        case .caption: 13
        case .unit: 13
        }
    }

    var weight: Font.Weight {
        switch self {
        case .tagNumber, .sideNumber, .cardNumber: .black
        case .pageTitle, .name, .label, .button, .unit: .heavy
        case .caption: .bold
        }
    }

    var style: Font.TextStyle {
        switch self {
        case .pageTitle, .tagNumber: .largeTitle
        case .sideNumber, .cardNumber: .title
        case .name, .button: .headline
        case .label: .subheadline
        case .caption, .unit: .footnote
        }
    }
}

private struct RoleFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(_ role: TextRole) {
        _size = ScaledMetric(wrappedValue: role.size, relativeTo: role.style)
        weight = role.weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .rounded))
    }
}

extension View {
    func textRole(_ role: TextRole) -> some View {
        modifier(RoleFont(role))
    }
}

extension Color {
    fileprivate init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(rgb: dark, alpha: darkAlpha) : UIColor(rgb: light, alpha: lightAlpha)
            })
    }
}

extension UIColor {
    fileprivate convenience init(rgb: UInt32, alpha: CGFloat) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}
