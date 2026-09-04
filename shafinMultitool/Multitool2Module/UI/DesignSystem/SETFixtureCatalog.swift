import SwiftUI

enum SETFixtureFamily: String, CaseIterable, Sendable {
    case foundations
    case components
    case entry
    case camera
    case pause
    case generator
    case library
    case storyboard
}

enum SETFixtureOrientation: String, CaseIterable, Sendable {
    case portrait
    case landscape
    case adaptive
}

struct SETFixtureDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let family: SETFixtureFamily
    let orientation: SETFixtureOrientation
}

enum SETFixtureCatalog {
    static let manifest: [SETFixtureDescriptor] = [
        descriptor("foundations.palette", .foundations),
        descriptor("foundations.typography", .foundations),
        descriptor("components.wordmark-horizontal", .components),
        descriptor("components.wordmark-stacked", .components),
        descriptor("components.poster-action", .components),
        descriptor("components.hud", .components),
        descriptor("components.marker-reflow", .components),
        descriptor("components.roll-capsule", .components),
        descriptor("components.leader", .components),
        descriptor("entry.resolving", .entry),
        descriptor("entry.requesting", .entry),
        descriptor("entry.ready", .entry),
        descriptor("entry.intro", .entry),
        descriptor("entry.permission", .entry),
        descriptor("entry.blocked-denied", .entry),
        descriptor("entry.blocked-restricted", .entry),
        descriptor("entry.blocked-unavailable", .entry),
        descriptor("entry.blocked-unknown", .entry),
        descriptor("camera.starting", .camera),
        descriptor("camera.interrupted", .camera),
        descriptor("camera.failed", .camera),
        descriptor("camera.seeking", .camera),
        descriptor("camera.keep", .camera),
        descriptor("camera.corrective", .camera),
        descriptor("camera.fallback", .camera),
        descriptor("camera.explanation", .camera),
        descriptor("camera.lens-switching", .camera),
        descriptor("camera.resuming", .camera),
        descriptor("camera.eco", .camera),
        descriptor("camera.pause-loading", .pause),
        descriptor("camera.pause-success", .pause),
        descriptor("camera.pause-empty", .pause),
        descriptor("camera.pause-failure", .pause),
        descriptor("generator.preflight", .generator, .landscape),
        descriptor("generator.clarification", .generator, .landscape),
        descriptor("generator.progress", .generator, .landscape),
        descriptor("generator.cancelled", .generator, .landscape),
        descriptor("generator.failure", .generator, .landscape),
        descriptor("generator.result", .generator, .landscape),
        descriptor("library.contact-sheet", .library, .landscape),
        descriptor("storyboard.result", .storyboard, .landscape)
    ]

    static let requiredLocales = SETGalleryLocale.allCases
    static let requiredAccessibilityModes = [
        "default",
        "reduce-motion",
        "reduce-transparency",
        "xxl"
    ]

    static let requiredFixtureIDs: Set<String> = Set(manifest.map(\.id))

#if DEBUG
    /// Generator fixtures stay on the real CommercialShell → Library →
    /// Generator route. Their payload is seeded by the existing ViewModel;
    /// no fixture scene is written to persistence.
    static let generatorStoryboardFixtureIDs: Set<String> = [
        "storyboard.result",
        "storyboard.tray-collapsed",
        "storyboard.tray-expanded",
        "storyboard.selection-reflow",
        "storyboard.inspector",
        "storyboard.editor-medium",
        "storyboard.editor-large",
        "storyboard.saving",
        "storyboard.validation-failure",
        "storyboard.delete-confirmation",
        "sheet.decision-trace"
    ]
#endif

    static func fixture(id: String?) -> SETFixtureDescriptor? {
        guard let id else { return nil }
        return manifest.first { $0.id == id }
    }

    private static func descriptor(
        _ id: String,
        _ family: SETFixtureFamily,
        _ orientation: SETFixtureOrientation = .adaptive
    ) -> SETFixtureDescriptor {
        SETFixtureDescriptor(id: id, family: family, orientation: orientation)
    }
}

#if DEBUG
struct SETGalleryLaunchConfiguration: Equatable, Sendable {
    static let galleryArgument = "-SHAFIN_DESIGN_SYSTEM_GALLERY"
    static let fixtureArgument = "-SHAFIN_SET_FIXTURE"
    static let localeArgument = "-SHAFIN_SET_LOCALE"
    static let reduceMotionArgument = "-SHAFIN_SET_REDUCE_MOTION"
    static let reduceTransparencyArgument = "-SHAFIN_SET_REDUCE_TRANSPARENCY"
    static let dynamicTypeArgument = "-SHAFIN_SET_DYNAMIC_TYPE"
    static let generatorStoryboardFixtureArgument = "-SHAFIN_GENERATOR_STORYBOARD_FIXTURE"
    static let decisionTraceFixtureArgument = "-SHAFIN_DECISION_TRACE_FIXTURE"

    let fixtureID: String?
    let locale: SETGalleryLocale
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let dynamicTypeSize: DynamicTypeSize

    init(arguments: [String]) {
        fixtureID = Self.value(after: Self.fixtureArgument, in: arguments)
        locale = SETGalleryLocale(
            rawValue: Self.value(after: Self.localeArgument, in: arguments) ?? "ru"
        ) ?? .ru
        reduceMotion = Self.boolValue(after: Self.reduceMotionArgument, in: arguments)
        reduceTransparency = Self.boolValue(after: Self.reduceTransparencyArgument, in: arguments)
        dynamicTypeSize = Self.value(after: Self.dynamicTypeArgument, in: arguments)?.lowercased() == "xxl"
            ? .accessibility2
            : .large
    }

    init(
        fixtureID: String? = nil,
        locale: SETGalleryLocale = .ru,
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        dynamicTypeSize: DynamicTypeSize = .large
    ) {
        self.fixtureID = fixtureID
        self.locale = locale
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.dynamicTypeSize = dynamicTypeSize
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func boolValue(after flag: String, in arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: flag) else { return false }
        guard arguments.indices.contains(index + 1) else { return true }
        let raw = arguments[index + 1]
        if raw.hasPrefix("-") { return true }
        return raw == "1" || ["true", "yes", "on"].contains(raw.lowercased())
    }
}
#endif
