import SwiftUI
import UIKit

struct SETRGBA: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    func withAlpha(_ alpha: Double) -> SETRGBA {
        SETRGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    func composited(over background: SETRGBA) -> SETRGBA {
        let outputAlpha = alpha + background.alpha * (1 - alpha)
        guard outputAlpha > 0 else { return SETRGBA(red: 0, green: 0, blue: 0, alpha: 0) }

        return SETRGBA(
            red: (red * alpha + background.red * background.alpha * (1 - alpha)) / outputAlpha,
            green: (green * alpha + background.green * background.alpha * (1 - alpha)) / outputAlpha,
            blue: (blue * alpha + background.blue * background.alpha * (1 - alpha)) / outputAlpha,
            alpha: outputAlpha
        )
    }

    static func contrastRatio(_ first: SETRGBA, _ second: SETRGBA) -> Double {
        // Semantic foreground tokens may carry opacity (for example
        // `text.secondary`).  Compare the rendered colors instead of treating
        // an alpha-bearing foreground as if it were opaque white.
        let firstRendered = first.alpha < 1 ? first.composited(over: second) : first
        let secondRendered = second.alpha < 1 ? second.composited(over: first) : second
        let firstLuminance = firstRendered.relativeLuminance
        let secondLuminance = secondRendered.relativeLuminance
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func rendered(over background: SETRGBA) -> SETRGBA {
        alpha < 1 ? composited(over: background) : self
    }

    private var relativeLuminance: Double {
        0.2126 * Self.linearized(red)
            + 0.7152 * Self.linearized(green)
            + 0.0722 * Self.linearized(blue)
    }

    private static func linearized(_ channel: Double) -> Double {
        channel <= 0.04045
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }
}

enum SETPalette {
    static let ink = SETRGBA(hex: 0x0B0B0E)
    /// Warm-white is named by semantic role and is used as a color token only;
    /// the gallery never treats it as a physical prop or texture.
    static let warmWhite = SETRGBA(hex: 0xF4F1EA)
    static let setOrange = SETRGBA(hex: 0xFF5A1F)
    static let surfaceSolid = SETRGBA(hex: 0x141419)
    static let blackGuide = SETRGBA(hex: 0x000000, alpha: 0.60)

    static let textPrimary = warmWhite
    static let textSecondary = warmWhite.withAlpha(0.64)
    static let textTertiary = warmWhite.withAlpha(0.40)
    static let hudScrim = ink.withAlpha(0.72)
    static let hairline = warmWhite.withAlpha(0.14)
    static let decorativeGrid = warmWhite.withAlpha(0.28)

}

extension ShapeStyle where Self == Color {
    static var setInk: Color { SETPalette.ink.color }
    static var setWarmWhite: Color { SETPalette.warmWhite.color }
    static var setOrange: Color { SETPalette.setOrange.color }
    static var setSurfaceSolid: Color { SETPalette.surfaceSolid.color }
    static var setTextPrimary: Color { SETPalette.textPrimary.color }
    static var setTextSecondary: Color { SETPalette.textSecondary.color }
    static var setTextTertiary: Color { SETPalette.textTertiary.color }
    static var setHUDScrim: Color { SETPalette.hudScrim.color }

    /// M11-012: the single transparency-aware surface. Under Reduce
    /// Transparency it resolves to the solid surface so text/controls stay
    /// legible over noisy camera content; otherwise the scrim. Call sites
    /// pass the environment value instead of branching locally.
    static func setAdaptiveScrim(reduceTransparency: Bool) -> Color {
        reduceTransparency ? Self.setSurfaceSolid : Self.setHUDScrim
    }
    static var setHairline: Color { SETPalette.hairline.color }

}
