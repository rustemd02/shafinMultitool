//
//  IntentClarificationRenderAcceptanceTests.swift
//  shafinMultitool
//
//  CC-I05 visual acceptance harness: renders the intent prompt at several
//  Dynamic Type sizes, orientations, appearances, and locales, asserts that
//  every configuration renders a non-empty image, and writes the PNGs for
//  human visual inspection (contrast, clipping, control overlap).
//

import SwiftUI
import XCTest
@testable import shafinMultitool

@MainActor
final class IntentClarificationRenderAcceptanceTests: XCTestCase {

    private var outputDirectory: URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("intent-prompt-acceptance", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func render(cue: CameraStyleCue,
                        width: CGFloat,
                        dynamicTypeSize: DynamicTypeSize,
                        colorScheme: ColorScheme,
                        locale: Locale) -> UIImage? {
        let view = SETCameraIntentClarificationPrompt(cue: cue, onAnswer: { _ in })
            .frame(width: width)
            .padding(8)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.colorScheme, colorScheme)
            .environment(\.locale, locale)
            .background(colorScheme == .dark ? Color.black : Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }

    func testEveryConfigurationRendersAndIsSavedForInspection() throws {
        let configurations: [(name: String, width: CGFloat, size: DynamicTypeSize, scheme: ColorScheme, locale: Locale)] = [
            ("portrait-large-light-ru", 390, .large, .light, Locale(identifier: "ru")),
            ("portrait-large-dark-en", 390, .large, .dark, Locale(identifier: "en")),
            ("landscape-large-light-ru", 844, .large, .light, Locale(identifier: "ru")),
            ("portrait-accessibility3-light-ru", 390, .accessibility3, .light, Locale(identifier: "ru")),
            ("portrait-accessibility5-dark-en", 390, .accessibility5, .dark, Locale(identifier: "en")),
            ("portrait-lowkey-large-light-ru", 390, .large, .light, Locale(identifier: "ru")),
            ("portrait-motionblur-accessibility3-dark-ru", 390, .accessibility3, .dark, Locale(identifier: "ru")),
        ]

        for configuration in configurations {
            let cue: CameraStyleCue = {
                switch configuration.name {
                case "portrait-lowkey-large-light-ru": return .lowKey
                case "portrait-motionblur-accessibility3-dark-ru": return .motionBlur
                default: return .tilt
                }
            }()
            let image = try XCTUnwrap(
                render(cue: cue,
                       width: configuration.width,
                       dynamicTypeSize: configuration.size,
                       colorScheme: configuration.scheme,
                       locale: configuration.locale),
                "renderer returned nil for \(configuration.name)"
            )
            XCTAssertGreaterThan(image.size.width, 0, configuration.name)
            XCTAssertGreaterThan(image.size.height, 0, configuration.name)

            let data = try XCTUnwrap(image.pngData(), configuration.name)
            XCTAssertGreaterThan(data.count, 1_000, "the prompt must render visible content: \(configuration.name)")
            try data.write(to: outputDirectory.appendingPathComponent("\(configuration.name).png"))
        }
        print("RENDERACCEPTANCE|dir=\(outputDirectory.path)")
    }

    /// Worst-case contrast is asserted from the style invariant instead of
    /// composite pixels: over a pure-white scene the scrim yields a panel of
    /// (1 - opacity) luminance, and the question uses the design text token.
    func testWorstCaseContrastOverAPureWhiteSceneMeetsAA() throws {
        let panelLuminance = IntentPromptStyle.panelOverWhiteLuminance
        let textColor = UIColor(SETPalette.textPrimary.color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(textColor.getRed(&r, green: &g, blue: &b, alpha: &a))
        let glyphLuminance = Double(0.2126 * r + 0.7152 * g + 0.0722 * b)
        let ratio = (glyphLuminance + 0.05) / (panelLuminance + 0.05)
        XCTAssertGreaterThanOrEqual(
            ratio, 4.5,
            "question text over a pure-white camera scene must meet WCAG AA: ratio \(ratio)"
        )
    }

    /// Hit-target invariant: both answers use the shared minimum target token,
    /// which must satisfy the 44pt HIG/WCAG requirement.
    func testAnswerHitTargetsMeetTheMinimum() {
        XCTAssertGreaterThanOrEqual(SETComponentMetric.minimumHitTarget, 44)
    }

    func testPromptHeightGrowsWithAccessibilityTextSizes() throws {
        let standard = try XCTUnwrap(render(cue: .tilt, width: 390, dynamicTypeSize: .large,
                                            colorScheme: .light, locale: Locale(identifier: "ru")))
        let accessibility = try XCTUnwrap(render(cue: .tilt, width: 390, dynamicTypeSize: .accessibility3,
                                                 colorScheme: .light, locale: Locale(identifier: "ru")))
        XCTAssertGreaterThan(
            accessibility.size.height, standard.size.height,
            "Dynamic Type must grow the prompt instead of clipping it"
        )
    }

    func testPromptFitsNarrowLandscapeWidths() throws {
        let narrow = try XCTUnwrap(render(cue: .silhouette, width: 320, dynamicTypeSize: .large,
                                          colorScheme: .light, locale: Locale(identifier: "en")))
        // The question itself must not require more vertical space than a
        // compact overlay can offer (two lines plus controls).
        XCTAssertLessThan(narrow.size.height, 260, "the prompt must stay compact next to capture controls")
    }
}
