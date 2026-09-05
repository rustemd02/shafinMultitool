import Foundation
import XCTest
@testable import shafinMultitool

final class CameraCoachEntryPresentationTests: XCTestCase {
    func testCanonicalIntroCopyUsesCatalogKeys() {
        XCTAssertEqual(CameraCoachEntryCopy.introTitleKey, .entryPoster)
        XCTAssertEqual(CameraCoachEntryCopy.introActionKey, .actionMain)
        XCTAssertEqual(CameraCoachEntryCopy.introBodyKey, .entryBody)
        XCTAssertEqual(CameraCoachEntryView.primaryActionIdentifier(for: .intro), CameraCoachEntryAccessibilityID.openCameraAction)
    }

    func testPermissionCopyUsesCameraOnlyCatalogKeys() {
        XCTAssertEqual(CameraCoachEntryCopy.permissionContextTitleKey, .permissionTitle)
        XCTAssertEqual(CameraCoachEntryCopy.permissionContextBodyKey, .permissionBody)
        XCTAssertEqual(CameraCoachEntryCopy.localProcessingKey, .entryLocalProcessing)
        XCTAssertEqual(CameraCoachEntryCopy.permissionContextActionKey, .permissionContinue)
        XCTAssertEqual(
            CameraCoachEntryView.primaryActionIdentifier(for: .permissionContext),
            CameraCoachEntryAccessibilityID.continueAction
        )
        XCTAssertFalse(CameraCoachEntryCopy.permissionContextBody.lowercased().contains("микрофон"))
        XCTAssertFalse(CameraCoachEntryCopy.permissionContextBody.lowercased().contains("фото"))
        XCTAssertFalse(CameraCoachEntryCopy.permissionContextBody.lowercased().contains("речь"))
    }

    func testBlockedReasonsRemainDistinctAndTruthful() {
        let cases: [(CameraCoachCameraBlockReason, SETCopyKey, String)] = [
            (.denied, .blockedDenied, CameraCoachEntryAccessibilityID.openSettingsAction),
            (.restricted, .blockedRestricted, CameraCoachEntryAccessibilityID.recheckAction),
            (.unavailable, .blockedUnavailable, CameraCoachEntryAccessibilityID.recheckAction),
            (.unknown, .blockedUnknown, CameraCoachEntryAccessibilityID.recheckAction)
        ]

        for (reason, key, primaryIdentifier) in cases {
            XCTAssertFalse(key.localizedString.isEmpty, String(describing: reason))
            XCTAssertEqual(
                CameraCoachEntryView.primaryActionIdentifier(for: .blocked(reason)),
                primaryIdentifier
            )
        }
        XCTAssertEqual(CameraCoachEntryCopy.blockedBodyKey, .entryBlockedBody)
        XCTAssertEqual(CameraCoachEntryCopy.settingsActionKey, .openSettings)
        XCTAssertEqual(CameraCoachEntryCopy.recheckActionKey, .checkAgain)
    }

    func testCameraEntryCopyHasRussianAndEnglishVisibleAndAccessibilityValues() {
        let keys: [SETCopyKey] = [
            .entryPoster,
            .entryBody,
            .actionMain,
            .permissionTitle,
            .permissionBody,
            .entryLocalProcessing,
            .permissionContinue,
            .blockedDenied,
            .blockedRestricted,
            .blockedUnavailable,
            .blockedUnknown,
            .entryBlockedBody,
            .entrySettingsFallback,
            .entryResolving,
            .entryRequesting,
            .entryReady,
            .accessibilityOpenCamera,
            .accessibilityContinue,
            .openSettings,
            .checkAgain,
            .accessibilityOpenSettings,
            .accessibilityRecheck
        ]

        for key in keys {
            let english = key.localizedString(locale: Locale(identifier: "en"))
            let russian = key.localizedString(locale: Locale(identifier: "ru"))
            XCTAssertFalse(english.isEmpty, "Missing English value for \(key.rawValue)")
            XCTAssertFalse(russian.isEmpty, "Missing Russian value for \(key.rawValue)")
            XCTAssertNotEqual(english, key.rawValue, "English falls back to key for \(key.rawValue)")
            XCTAssertNotEqual(russian, key.rawValue, "Russian falls back to key for \(key.rawValue)")
        }
    }

    func testEveryRenderedPhaseHasStableRootAndActionIdentifiers() {
        let phases: [CameraCoachEntryPhase] = [
            .resolving,
            .intro,
            .permissionContext,
            .requesting,
            .ready,
            .blocked(.denied),
            .blocked(.restricted),
            .blocked(.unavailable),
            .blocked(.unknown)
        ]

        let roots = phases.map(CameraCoachEntryView.rootAccessibilityIdentifier(for:))
        XCTAssertEqual(Set(roots).count, roots.count)
        XCTAssertTrue(roots.allSatisfy { $0.hasPrefix("camera-coach-entry-") })

        let actions = [
            CameraCoachEntryAccessibilityID.openCameraAction,
            CameraCoachEntryAccessibilityID.continueAction,
            CameraCoachEntryAccessibilityID.openSettingsAction,
            CameraCoachEntryAccessibilityID.recheckAction
        ]
        XCTAssertEqual(Set(actions).count, actions.count)
        XCTAssertTrue(actions.allSatisfy { $0.hasPrefix("camera-coach-entry-") })
    }

    func testResolvingRequestingAndReadyHaveNoEntryAction() {
        XCTAssertNil(CameraCoachEntryView.primaryActionIdentifier(for: .resolving))
        XCTAssertNil(CameraCoachEntryView.primaryActionIdentifier(for: .requesting))
        XCTAssertNil(CameraCoachEntryView.primaryActionIdentifier(for: .ready))
    }

    func testEntryVisualContractUsesV26MarkersAndNoForbiddenLayers() throws {
        XCTAssertEqual(
            CameraCoachEntryVisualPolicy.sourceMarkers,
            [
                "set-os-two-registers",
                "poster-typography-bilingual",
                "single-orange-accent-wcag",
                "mono-hud",
                "glass-mark-annotation",
                "leader-countdown",
                "state-table-camera-coach",
                "motion-respects-reduce-motion"
            ]
        )

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Multitool2Module/EntryFlow/CameraCoachEntryView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        for forbidden in ["CameraPreview", "ProgressView", "Material", "UIVisualEffectView", "CAGradientLayer", ".shadow", "LinearGradient"] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    func testEntrySurfaceDoesNotExposeLiveControls() {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Multitool2Module/EntryFlow/CameraCoachEntryView.swift")
        let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(source.contains("record"))
        XCTAssertFalse(source.contains("pause"))
        XCTAssertFalse(source.contains("Deep Review"))
    }

    func testEntryUsesGeometrySplitAndOwnerIssuedMarkerRail() throws {
        XCTAssertFalse(SETEntryLayout.resolve(container: CGSize(width: 390, height: 844)).isSplit)
        let standardLandscape = SETEntryLayout.resolve(container: CGSize(width: 844, height: 390))
        let accessibilityLandscape = SETEntryLayout.resolve(
            container: CGSize(width: 844, height: 390),
            accessibilityType: true
        )
        XCTAssertTrue(standardLandscape.isSplit)
        XCTAssertTrue(accessibilityLandscape.isSplit)
        XCTAssertTrue(accessibilityLandscape.isAccessibilityType)
        XCTAssertLessThan(
            accessibilityLandscape.landscapeRailFraction,
            standardLandscape.landscapeRailFraction,
            "AX landscape must reserve more width for the readable phase column."
        )

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Multitool2Module/EntryFlow/CameraCoachEntryView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("SETEntryLayout.resolve("))
        XCTAssertTrue(source.contains("accessibilityType: dynamicTypeSize.isAccessibilitySize"))
        XCTAssertTrue(source.contains("GlassMarkGuide"))
        XCTAssertTrue(source.contains("drawProgress: markerDrawProgress"))
        XCTAssertTrue(source.contains("value: markerDrawProgress"))
        XCTAssertTrue(source.contains("SETMotion.markerDrawDuration"))
        XCTAssertTrue(source.contains("SETMotion.reducedMotionCrossfadeDuration"))
        XCTAssertFalse(source.contains("SETMarkerDrawGuide"))
        XCTAssertFalse(source.contains("resolvedMarkerEventID"))
        XCTAssertFalse(source.contains("markerKind: .outline"))
    }

    func testEntryCommandsUseTheSharedCommandLabelOwner() throws {
        let entrySourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Multitool2Module/EntryFlow/CameraCoachEntryView.swift")
        let entrySource = try String(contentsOf: entrySourceURL, encoding: .utf8)

        XCTAssertTrue(entrySource.contains("SETDigitalAction(title: actionTitle"))
        XCTAssertTrue(entrySource.contains("SETCommandLabel(key: secondaryTitle"))
        XCTAssertTrue(
            entrySource.contains(".accessibilityLabel(Text(secondaryTitle.localizedTextKey))"),
            "The visible command uses SETCommandLabel, while the spoken label remains localized."
        )

        let designSystemSourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Multitool2Module/UI/DesignSystem/SETComponents.swift")
        let designSystemSource = try String(contentsOf: designSystemSourceURL, encoding: .utf8)
        guard
            let actionStart = designSystemSource.range(of: "struct SETDigitalAction"),
            let actionEnd = designSystemSource.range(of: "enum SETTallyMode", range: actionStart.upperBound..<designSystemSource.endIndex)
        else {
            XCTFail("SETDigitalAction source boundary is missing")
            return
        }

        let actionSource = String(designSystemSource[actionStart.lowerBound..<actionEnd.lowerBound])
        XCTAssertTrue(actionSource.contains("SETCommandLabel(key: title)"))
        XCTAssertFalse(actionSource.contains("uiBodyFont"))
        XCTAssertTrue(actionSource.contains("dynamicTypeSize.isAccessibilitySize"))
        XCTAssertTrue(actionSource.contains("VStack(alignment: .leading"))
        XCTAssertTrue(actionSource.contains("HStack(alignment: .center"))
        XCTAssertTrue(actionSource.contains("SETTypography.font(.hudMono"))
    }
}
