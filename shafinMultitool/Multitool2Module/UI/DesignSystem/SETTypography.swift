import SwiftUI
import UIKit
import Foundation

enum SETFontRole: String, CaseIterable, Sendable {
    case wordmark
    case display
    case hudMono
    case screenplay
    case hand

    var postScriptName: String {
        switch self {
        case .wordmark: "BebasNeue-Regular"
        case .display: "Oswald-Regular"
        case .hudMono: "JetBrainsMono-Regular"
        case .screenplay: "PTMono-Regular"
        case .hand: "Caveat-Regular"
        }
    }

    var bundleFilename: String {
        switch self {
        case .wordmark: "BebasNeue-Regular.ttf"
        case .display: "Oswald-Variable.ttf"
        case .hudMono: "JetBrainsMono-Variable.ttf"
        case .screenplay: "PTM55FT.ttf"
        case .hand: "Caveat-Variable.ttf"
        }
    }

    var localizedTextAllowed: Bool { self != .wordmark }
}

struct SETFontAsset: Equatable, Sendable {
    let role: SETFontRole
    let filename: String
    let postScriptName: String
    let sha256: String
}

enum SETTypography {
    static let assets: [SETFontAsset] = [
        SETFontAsset(
            role: .wordmark,
            filename: "BebasNeue-Regular.ttf",
            postScriptName: "BebasNeue-Regular",
            sha256: "08e4623805102d819f58601e46e345648846075e363b2ceb23313c2d1c83ec73"
        ),
        SETFontAsset(
            role: .display,
            filename: "Oswald-Variable.ttf",
            postScriptName: "Oswald-Regular",
            sha256: "5b38c246e255a12f5712d640d56bcced0472466fc68983d2d0410ec0457c2817"
        ),
        SETFontAsset(
            role: .hudMono,
            filename: "JetBrainsMono-Variable.ttf",
            postScriptName: "JetBrainsMono-Regular",
            sha256: "48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"
        ),
        SETFontAsset(
            role: .screenplay,
            filename: "PTM55FT.ttf",
            postScriptName: "PTMono-Regular",
            sha256: "cbe732b3b8fd211fd986ebdfc9b870ddeca4faab0bb5425fc509b37f9b4ac804"
        ),
        SETFontAsset(
            role: .hand,
            filename: "Caveat-Variable.ttf",
            postScriptName: "Caveat-Regular",
            sha256: "0bdb6b660482d31531b3945849fba5916b3ef8695da7024a9e6b9ee3c4157988"
        )
    ]

    static let productCharacterSet = """
    АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ
    абвгдеёжзийклмнопрстуфхцчшщъыьэюя
    ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
    0123456789 №—–…«»“”„!?.,:;()[]{}+-×/%&@#_'\"\u{00A0}
    """

    static func fontURL(
        for role: SETFontRole,
        in bundle: Bundle = .main
    ) -> URL? {
        let resourceName = role.bundleFilename.replacingOccurrences(of: ".ttf", with: "")
        return bundle.url(forResource: resourceName, withExtension: "ttf")
    }

    static func uiBodyFont(weight: Font.Weight = .regular) -> Font {
        Font.system(.body, design: .default).weight(weight)
    }

    static func uiLabelFont(weight: Font.Weight = .regular) -> Font {
        Font.system(.subheadline, design: .default).weight(weight)
    }

    static func font(_ role: SETFontRole, size: CGFloat) -> Font {
        let fallback: Font
        switch role {
        case .wordmark:
            fallback = .system(size: size, weight: .semibold, design: .default)
        case .display:
            fallback = .system(size: size, weight: .bold, design: .default)
        case .hudMono, .screenplay:
            fallback = .system(size: size, weight: .regular, design: .monospaced)
        case .hand:
            fallback = .system(size: size, weight: .regular, design: .rounded)
        }

        guard UIFont(name: role.postScriptName, size: size) != nil else { return fallback }
        return .custom(role.postScriptName, fixedSize: size)
    }

    /// Uses the same SET font role while allowing meaningful interface copy to
    /// follow the caller's Dynamic Type text style. Decorative display copy
    /// continues to use `font(_:size:)` and its fixed-size contract.
    static func scaledFont(
        _ role: SETFontRole,
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        let fallback: Font
        switch role {
        case .wordmark:
            fallback = .system(textStyle, design: .default).weight(.semibold)
        case .display:
            fallback = .system(textStyle, design: .default).weight(.bold)
        case .hudMono, .screenplay:
            fallback = .system(textStyle, design: .monospaced)
        case .hand:
            fallback = .system(textStyle, design: .rounded)
        }

        guard UIFont(name: role.postScriptName, size: size) != nil else { return fallback }
        return .custom(role.postScriptName, size: size, relativeTo: textStyle)
    }

    static func uiFont(_ role: SETFontRole, size: CGFloat) -> UIFont {
        if let font = UIFont(name: role.postScriptName, size: size) {
            return font
        }

        switch role {
        case .wordmark:
            return .systemFont(ofSize: size, weight: .semibold)
        case .display:
            return .systemFont(ofSize: size, weight: .bold)
        case .hudMono, .screenplay:
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .hand:
            return .systemFont(ofSize: size, weight: .regular)
        }
    }

    static func missingRegisteredRoles() -> [SETFontRole] {
        SETFontRole.allCases.filter { UIFont(name: $0.postScriptName, size: 17) == nil }
    }
}

extension View {
    func setDisplayTracking() -> some View {
        tracking(-0.01 * SETTypographySize.displayMedium)
    }

    func setMonoTracking() -> some View {
        tracking(0.05 * SETTypographySize.label)
    }
}
